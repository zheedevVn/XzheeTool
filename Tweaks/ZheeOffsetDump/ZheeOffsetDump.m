// ZheeOffsetDump.m — Dylib dump offset (ObjC runtime) của binary chính.
//
// Inject vào app mục tiêu (LC_LOAD_DYLIB). Không hook, không sửa gì —
// chỉ đọc runtime, ghi kết quả ra file, không ảnh hưởng app.
//
// Chạy tự động sau khi app mở ~2s (chạy nền, không block UI).
// Output: <App Documents>/ZheeOffsets.txt
//   - Header: bundle ID, executable, image base, ASLR slide, danh sách image đã load.
//   - Từng class (chỉ method có IMP nằm trong binary chính):
//       [ClassName] +/- selector | type encoding | IMP=0x... | offset=0x...
//     + ivar: name, offset trong object.
//   - offset = IMP - imageBase (ổn định qua các lần chạy, không phụ thuộc ASLR).
//
// Build: xcrun -sdk iphoneos clang -arch arm64 -dynamiclib -fobjc-arc
//        -isysroot $(xcrun --sdk iphoneos --show-sdk-path)
//        -miphoneos-version-min=14.0 -framework Foundation
//        -o ZheeOffsetDump.dylib ZheeOffsetDump.m

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static int cmpClassNames(const void *a, const void *b) {
    const char *na = class_getName(*(Class *)a);
    const char *nb = class_getName(*(Class *)b);
    return strcmp(na ? na : "", nb ? nb : "");
}

static int cmpMethodNames(const void *a, const void *b) {
    const char *na = sel_getName(method_getName(*(Method *)a));
    const char *nb = sel_getName(method_getName(*(Method *)b));
    return strcmp(na ? na : "", nb ? nb : "");
}

static void ZheeDumpOffsets(void) {
    @autoreleasepool {
        const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
        if (!mh) { NSLog(@"[ZheeOffsetDump] no main image"); return; }
        intptr_t slide = _dyld_get_image_vmaddr_slide(0);
        uintptr_t base = (uintptr_t)mh; // = __TEXT.vmaddr + slide

        // Lấy vmsize của __TEXT để biết khoảng địa chỉ của binary chính.
        uint64_t textSize = 0;
        const struct load_command *lc = (const struct load_command *)((const char *)mh + sizeof(struct mach_header_64));
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                if (strncmp(seg->segname, "__TEXT", 6) == 0) textSize = seg->vmsize;
            }
            lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
        }
        uintptr_t end = base + (uintptr_t)textSize;
        NSString *exePath = [NSString stringWithUTF8String:_dyld_get_image_name(0) ?: ""];

        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"# ZheeOffsetDump\n"];
        [out appendFormat:@"# bundle: %@\n", NSBundle.mainBundle.bundleIdentifier ?: @"?"];
        [out appendFormat:@"# executable: %@\n", exePath];
        [out appendFormat:@"# imageBase: 0x%lx  slide: 0x%lx  __TEXT size: 0x%llx\n",
                          (unsigned long)base, (unsigned long)slide, (unsigned long long)textSize];
        [out appendFormat:@"# offset = IMP - imageBase (khong phu thuoc ASLR)\n"];
        [out appendFormat:@"# --- loaded images ---\n"];
        uint32_t imgCount = _dyld_image_count();
        for (uint32_t i = 0; i < imgCount; i++) {
            const char *name = _dyld_get_image_name(i);
            [out appendFormat:@"# [%u] base=0x%lx %s\n", i,
                              (unsigned long)_dyld_get_image_header(i), name ? name : "?"];
        }
        [out appendFormat:@"# --- classes (chi method trong binary chinh) ---\n"];

        int clsCount = objc_getClassList(NULL, 0);
        if (clsCount <= 0) { NSLog(@"[ZheeOffsetDump] no classes"); return; }
        Class *classes = malloc(sizeof(Class) * (size_t)clsCount);
        clsCount = objc_getClassList(classes, clsCount);
        qsort(classes, (size_t)clsCount, sizeof(Class), cmpClassNames);

        long totalClasses = 0, totalMethods = 0, totalIvars = 0;
        for (int ci = 0; ci < clsCount; ci++) {
            Class cls = classes[ci];
            const char *clsName = class_getName(cls);
            if (!clsName) continue;

            // Gom method instance + class method, chỉ giữ method trong binary chính.
            NSMutableString *clsOut = [NSMutableString string];
            long keptMethods = 0;
            for (int pass = 0; pass < 2; pass++) {
                Class target = (pass == 0) ? cls : object_getClass(cls);
                if (!target) continue;
                unsigned int mcount = 0;
                Method *methods = class_copyMethodList(target, &mcount);
                if (!methods) continue;
                qsort(methods, mcount, sizeof(Method), cmpMethodNames);
                for (unsigned int mi = 0; mi < mcount; mi++) {
                    IMP imp = method_getImplementation(methods[mi]);
                    uintptr_t addr = (uintptr_t)imp;
                    if (addr < base || addr >= end) continue; // method ngoài binary chính
                    const char *sel = sel_getName(method_getName(methods[mi]));
                    const char *type = method_getTypeEncoding(methods[mi]);
                    [clsOut appendFormat:@"[%s] %c%s | %s | IMP=0x%lx | offset=0x%lx\n",
                                         clsName, (pass == 0 ? '-' : '+'), sel ? sel : "?",
                                         type ? type : "?",
                                         (unsigned long)addr, (unsigned long)(addr - base)];
                    keptMethods++;
                }
                free(methods);
            }

            // Ivar (offset trong object, không phụ thuộc ASLR).
            unsigned int icount = 0;
            Ivar *ivars = class_copyIvarList(cls, &icount);
            NSMutableString *ivarOut = [NSMutableString string];
            long keptIvars = 0;
            if (ivars) {
                for (unsigned int ii = 0; ii < icount; ii++) {
                    const char *iname = ivar_getName(ivars[ii]);
                    const char *itype = ivar_getTypeEncoding(ivars[ii]);
                    [ivarOut appendFormat:@"[%s] ivar %s (%s) | offset=0x%lx\n",
                                         clsName, iname ? iname : "?",
                                         itype ? itype : "?",
                                         (unsigned long)ivar_getOffset(ivars[ii])];
                    keptIvars++;
                }
                free(ivars);
            }

            if (keptMethods == 0 && keptIvars == 0) continue;
            [out appendString:clsOut];
            [out appendString:ivarOut];
            totalClasses++;
            totalMethods += keptMethods;
            totalIvars += keptIvars;
        }
        free(classes);

        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [docs stringByAppendingPathComponent:@"ZheeOffsets.txt"];
        NSError *err = nil;
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            NSLog(@"[ZheeOffsetDump] write failed: %@", err);
        } else {
            NSLog(@"[ZheeOffsetDump] wrote %@ (%ld classes, %ld methods, %ld ivars)",
                  path, totalClasses, totalMethods, totalIvars);
        }
    }
}

__attribute__((constructor)) static void ZheeOffsetDumpInit(void) {
    // Đợi app mở xong rồi dump nền, không block UI.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        @try { ZheeDumpOffsets(); } @catch (NSException *e) {
            NSLog(@"[ZheeOffsetDump] exception: %@", e);
        }
    });
}
