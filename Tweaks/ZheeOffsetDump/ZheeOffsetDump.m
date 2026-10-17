// ZheeOffsetDump.m v2 — Dylib dump offset: framework (ObjC) + metadata (il2cpp).
//
// Inject vào app mục tiêu (LC_LOAD_DYLIB). Không hook, không sửa gì —
// chỉ đọc runtime, ghi kết quả ra file.
//
// Cách hoạt động (giống cách Frida il2cpp-bridge dùng, nhưng native,
// chạy độc lập khi inject, không cần Frida server / máy tính):
//  - ObjC: quét toàn bộ class, nhóm theo từng image (binary chính + từng
//    framework), offset = IMP - base của image chứa nó.
//  - il2cpp (app Unity): gọi trực tiếp il2cpp API qua dlsym
//    (domain -> assembly -> image -> class -> method/field), lấy
//    methodPointer (field đầu tiên của MethodInfo, ổn định qua các bản
//    il2cpp), offset = methodPointer - base của image chứa nó.
//    Field offset lấy qua il2cpp_field_get_offset.
//  - Metadata: đọc header của global-metadata.dat trong bundle
//    (sanity, version, số lượng string/type/method/field) + đường dẫn file,
//    để dùng với Il2CppDumper / Frida trên máy tính.
//
// Chạy tự động sau khi app mở ~2s (chạy nền). Nếu il2cpp chưa khởi tạo,
// thử lại mỗi 2s, tối đa 5 lần.
// Output: <App Documents>/ZheeOffsets.txt
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

// ---------------------------------------------------------------------------
// il2cpp API (opaque types, dlsym lúc runtime — không link cứng)
// ---------------------------------------------------------------------------
typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct FieldInfo FieldInfo;
typedef struct Il2CppType Il2CppType;

typedef Il2CppDomain *(*FnDomainGet)(void);
typedef const Il2CppAssembly **(*FnDomainAssemblies)(const Il2CppDomain *, size_t *);
typedef const Il2CppImage *(*FnAssemblyImage)(const Il2CppAssembly *);
typedef const char *(*FnImageName)(const Il2CppImage *);
typedef size_t (*FnImageClassCount)(const Il2CppImage *);
typedef const Il2CppClass *(*FnImageGetClass)(const Il2CppImage *, size_t);
typedef const MethodInfo *(*FnClassMethods)(const Il2CppClass *, void **);
typedef const FieldInfo *(*FnClassFields)(const Il2CppClass *, void **);
typedef const char *(*FnClassName)(const Il2CppClass *);
typedef const char *(*FnClassNamespace)(const Il2CppClass *);
typedef const char *(*FnMethodName)(const MethodInfo *);
typedef const Il2CppType *(*FnMethodRet)(const MethodInfo *);
typedef uint8_t (*FnMethodParamCount)(const MethodInfo *);
typedef const Il2CppType *(*FnMethodParam)(const MethodInfo *, uint32_t);
typedef const char *(*FnFieldName)(const FieldInfo *);
typedef size_t (*FnFieldOffset)(const FieldInfo *);
typedef const Il2CppType *(*FnFieldType)(const FieldInfo *);
typedef char *(*FnTypeName)(const Il2CppType *);
typedef void (*FnFree)(void *);

static void *ZheeSym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

// ---------------------------------------------------------------------------
// Image range: base + __TEXT vmsize của image thứ i
// ---------------------------------------------------------------------------
static BOOL ZheeImageRange(uint32_t idx, uintptr_t *outBase, uintptr_t *outEnd) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(idx);
    if (!mh) return NO;
    uintptr_t base = (uintptr_t)mh;
    uint64_t textSize = 0;
    const struct load_command *lc = (const struct load_command *)((const char *)mh + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, "__TEXT", 6) == 0) textSize = seg->vmsize;
        }
        lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
    }
    *outBase = base;
    *outEnd = base + (uintptr_t)textSize;
    return YES;
}

// Image nào chứa địa chỉ p? Trả index, hoặc -1.
static int ZheeImageContaining(uintptr_t p, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t b = 0, e = 0;
        if (ZheeImageRange(i, &b, &e) && p >= b && p < e) return (int)i;
    }
    return -1;
}

static int cmpClassNames(const void *a, const void *b) {
    return strcmp(class_getName(*(Class *)a) ?: "", class_getName(*(Class *)b) ?: "");
}
static int cmpMethodNames(const void *a, const void *b) {
    return strcmp(sel_getName(method_getName(*(Method *)a)) ?: "",
                  sel_getName(method_getName(*(Method *)b)) ?: "");
}

// ---------------------------------------------------------------------------
// Dump
// ---------------------------------------------------------------------------
static BOOL gIl2CppDone = NO;

static void ZheeDumpOffsets(void) {
    @autoreleasepool {
        uint32_t imgCount = _dyld_image_count();
        NSString *exePath = [NSString stringWithUTF8String:_dyld_get_image_name(0) ?: ""];
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"# ZheeOffsetDump v2\n"];
        [out appendFormat:@"# bundle: %@\n", NSBundle.mainBundle.bundleIdentifier ?: @"?"];
        [out appendFormat:@"# executable: %@\n", exePath];
        [out appendFormat:@"# offset = address - base cua image chua no (khong phu thuoc ASLR)\n"];
        [out appendFormat:@"# --- loaded images (framework + binary) ---\n"];
        for (uint32_t i = 0; i < imgCount; i++) {
            uintptr_t b = 0, e = 0;
            ZheeImageRange(i, &b, &e);
            const char *name = _dyld_get_image_name(i);
            [out appendFormat:@"# [%u] base=0x%lx size=0x%lx %s\n", i,
                              (unsigned long)b, (unsigned long)(e - b), name ? name : "?"];
        }

        // ---- Section 1: ObjC, nhóm theo image ----
        [out appendFormat:@"\n# --- ObjC per-image ---\n"];
        NSMutableArray<NSMutableString *> *perImage = [NSMutableArray array];
        for (uint32_t i = 0; i < imgCount; i++) [perImage addObject:[NSMutableString string]];
        long totalObjCClasses = 0, totalObjCMethods = 0;

        int clsCount = objc_getClassList(NULL, 0);
        if (clsCount > 0) {
            Class *classes = malloc(sizeof(Class) * (size_t)clsCount);
            clsCount = objc_getClassList(classes, clsCount);
            qsort(classes, (size_t)clsCount, sizeof(Class), cmpClassNames);
            for (int ci = 0; ci < clsCount; ci++) {
                Class cls = classes[ci];
                const char *clsName = class_getName(cls);
                if (!clsName) continue;
                // Gom method theo image chứa IMP.
                NSMutableDictionary<NSNumber *, NSMutableString *> *buckets = [NSMutableDictionary dictionary];
                for (int pass = 0; pass < 2; pass++) {
                    Class target = (pass == 0) ? cls : object_getClass(cls);
                    if (!target) continue;
                    unsigned int mcount = 0;
                    Method *methods = class_copyMethodList(target, &mcount);
                    if (!methods) continue;
                    qsort(methods, mcount, sizeof(Method), cmpMethodNames);
                    for (unsigned int mi = 0; mi < mcount; mi++) {
                        uintptr_t addr = (uintptr_t)method_getImplementation(methods[mi]);
                        int img = ZheeImageContaining(addr, imgCount);
                        if (img < 0) continue;
                        uintptr_t b = 0, e = 0;
                        ZheeImageRange((uint32_t)img, &b, &e);
                        const char *sel = sel_getName(method_getName(methods[mi]));
                        const char *type = method_getTypeEncoding(methods[mi]);
                        NSMutableString *buf = buckets[@(img)];
                        if (!buf) { buf = [NSMutableString string]; buckets[@(img)] = buf; }
                        [buf appendFormat:@"[%s] %c%s | %s | IMP=0x%lx | offset=0x%lx\n",
                                          clsName, (pass == 0 ? '-' : '+'), sel ? sel : "?",
                                          type ? type : "?",
                                          (unsigned long)addr, (unsigned long)(addr - b)];
                    }
                    free(methods);
                }
                // Ivar: thuộc về class, ghi vào image chứa class (ước lượng qua method đầu tiên).
                // Nếu class không có method nào trong image nào, bỏ qua.
                if (buckets.count == 0) continue;
                totalObjCClasses++;
                for (NSNumber *imgKey in buckets) {
                    NSMutableString *dst = perImage[imgKey.intValue];
                    [dst appendString:buckets[imgKey]];
                    totalObjCMethods += (long)[[buckets[imgKey] componentsSeparatedByString:@"\n"] count] - 1;
                }
                unsigned int icount = 0;
                Ivar *ivars = class_copyIvarList(cls, &icount);
                if (ivars && icount > 0) {
                    // Ghi ivar vào image của method đầu tiên của class (nếu có).
                    NSNumber *firstImg = buckets.allKeys.firstObject;
                    if (firstImg) {
                        NSMutableString *dst = perImage[firstImg.intValue];
                        for (unsigned int ii = 0; ii < icount; ii++) {
                            [dst appendFormat:@"[%s] ivar %s (%s) | offset=0x%lx\n",
                                              clsName,
                                              ivar_getName(ivars[ii]) ?: "?",
                                              ivar_getTypeEncoding(ivars[ii]) ?: "?",
                                              (unsigned long)ivar_getOffset(ivars[ii])];
                        }
                    }
                    free(ivars);
                }
            }
            free(classes);
        }
        for (uint32_t i = 0; i < imgCount; i++) {
            NSMutableString *buf = perImage[i];
            if (buf.length == 0) continue;
            const char *name = _dyld_get_image_name(i);
            [out appendFormat:@"\n## image [%u] %s\n", i, name ? name : "?"];
            [out appendString:buf];
        }
        [out appendFormat:@"# ObjC: %ld classes, %ld methods\n", totalObjCClasses, totalObjCMethods];

        // ---- Section 2: il2cpp (Unity) ----
        [out appendFormat:@"\n# --- il2cpp (Unity) ---\n"];
        FnDomainGet domainGet = (FnDomainGet)ZheeSym("il2cpp_domain_get");
        if (!domainGet) {
            [out appendFormat:@"# khong phai app Unity (khong co il2cpp_domain_get)\n"];
            gIl2CppDone = YES; // không phải Unity -> không retry
        } else {
            Il2CppDomain *domain = domainGet();
            if (!domain) {
                [out appendFormat:@"# il2cpp chua khoi tao (thu lai sau)\n"];
            } else {
                FnDomainAssemblies assembliesFn = (FnDomainAssemblies)ZheeSym("il2cpp_domain_get_assemblies");
                FnAssemblyImage assemblyImage = (FnAssemblyImage)ZheeSym("il2cpp_assembly_get_image");
                FnImageName imageName = (FnImageName)ZheeSym("il2cpp_image_get_name");
                FnImageClassCount classCountFn = (FnImageClassCount)ZheeSym("il2cpp_image_get_class_count");
                FnImageGetClass getClass = (FnImageGetClass)ZheeSym("il2cpp_image_get_class");
                FnClassMethods classMethods = (FnClassMethods)ZheeSym("il2cpp_class_get_methods");
                FnClassFields classFields = (FnClassFields)ZheeSym("il2cpp_class_get_fields");
                FnClassName className = (FnClassName)ZheeSym("il2cpp_class_get_name");
                FnClassNamespace classNs = (FnClassNamespace)ZheeSym("il2cpp_class_get_namespace");
                FnMethodName methodName = (FnMethodName)ZheeSym("il2cpp_method_get_name");
                FnMethodRet methodRet = (FnMethodRet)ZheeSym("il2cpp_method_get_return_type");
                FnMethodParamCount paramCount = (FnMethodParamCount)ZheeSym("il2cpp_method_get_param_count");
                FnMethodParam paramAt = (FnMethodParam)ZheeSym("il2cpp_method_get_param");
                FnFieldName fieldName = (FnFieldName)ZheeSym("il2cpp_field_get_name");
                FnFieldOffset fieldOffset = (FnFieldOffset)ZheeSym("il2cpp_field_get_offset");
                FnFieldType fieldType = (FnFieldType)ZheeSym("il2cpp_field_get_type");
                FnTypeName typeName = (FnTypeName)ZheeSym("il2cpp_type_get_name");
                FnFree il2cppFree = (FnFree)ZheeSym("il2cpp_free");
                if (!assembliesFn || !assemblyImage || !getClass || !classMethods || !className) {
                    [out appendFormat:@"# thieu il2cpp API (khong dump duoc)\n"];
                    gIl2CppDone = YES;
                } else {
                    size_t asmCount = 0;
                    const Il2CppAssembly **asms = assembliesFn(domain, &asmCount);
                    long totalIl2CppClasses = 0, totalIl2CppMethods = 0, totalIl2CppFields = 0;
                    for (size_t ai = 0; ai < asmCount; ai++) {
                        const Il2CppImage *img = assemblyImage(asms[ai]);
                        if (!img) continue;
                        const char *asmName = imageName ? (imageName(img) ?: "?") : "?";
                        size_t cc = classCountFn ? classCountFn(img) : 0;
                        for (size_t ci = 0; ci < cc; ci++) {
                            const Il2CppClass *klass = getClass(img, ci);
                            if (!klass) continue;
                            const char *kName = className(klass) ?: "?";
                            const char *kNs = classNs ? (classNs(klass) ?: "") : "";
                            [out appendFormat:@"\n## il2cpp class %s.%s (assembly %s)\n", kNs, kName, asmName];
                            totalIl2CppClasses++;
                            // Methods
                            if (classMethods) {
                                void *iter = NULL;
                                const MethodInfo *m = NULL;
                                while ((m = classMethods(klass, &iter)) != NULL) {
                                    // methodPointer = field đầu tiên của MethodInfo.
                                    void *mp = *(void **)m;
                                    const char *mName = methodName ? (methodName(m) ?: "?") : "?";
                                    NSMutableString *sig = [NSMutableString string];
                                    if (methodRet && typeName) {
                                        char *rt = typeName(methodRet(m));
                                        [sig appendFormat:@"%s", rt ?: "?"];
                                        if (rt && il2cppFree) il2cppFree(rt);
                                    } else [sig appendString:@"?"];
                                    [sig appendString:@" ("];
                                    if (paramCount && paramAt && typeName) {
                                        uint8_t pc = paramCount(m);
                                        for (uint8_t pi = 0; pi < pc; pi++) {
                                            char *pt = typeName(paramAt(m, pi));
                                            [sig appendFormat:@"%s%s", pi ? ", " : "", pt ?: "?"];
                                            if (pt && il2cppFree) il2cppFree(pt);
                                        }
                                    }
                                    [sig appendString:@")"];
                                    int imgIdx = ZheeImageContaining((uintptr_t)mp, imgCount);
                                    uintptr_t b = 0, e = 0;
                                    if (imgIdx >= 0) ZheeImageRange((uint32_t)imgIdx, &b, &e);
                                    [out appendFormat:@"  method %s | %s | methodPtr=0x%lx | image=%d | offset=0x%lx\n",
                                                      mName, sig,
                                                      (unsigned long)(uintptr_t)mp, imgIdx,
                                                      imgIdx >= 0 ? (unsigned long)((uintptr_t)mp - b) : 0];
                                    totalIl2CppMethods++;
                                }
                            }
                            // Fields
                            if (classFields) {
                                void *iter = NULL;
                                const FieldInfo *f = NULL;
                                while ((f = classFields(klass, &iter)) != NULL) {
                                    const char *fName = fieldName ? (fieldName(f) ?: "?") : "?";
                                    NSString *ft = @"?";
                                    if (fieldType && typeName) {
                                        char *tn = typeName(fieldType(f));
                                        if (tn) { ft = [NSString stringWithUTF8String:tn]; if (il2cppFree) il2cppFree(tn); }
                                    }
                                    size_t fo = fieldOffset ? fieldOffset(f) : 0;
                                    [out appendFormat:@"  field %s (%@) | fieldOffset=0x%lx\n",
                                                      fName, ft, (unsigned long)fo];
                                    totalIl2CppFields++;
                                }
                            }
                        }
                    }
                    [out appendFormat:@"# il2cpp: %ld classes, %ld methods, %ld fields\n",
                                      totalIl2CppClasses, totalIl2CppMethods, totalIl2CppFields];
                    gIl2CppDone = YES;
                }
            }
        }

        // ---- Section 3: metadata file ----
        [out appendFormat:@"\n# --- metadata (global-metadata.dat) ---\n"];
        NSString *metaPath = nil;
        NSArray<NSString *> *candidates = @[
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"],
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Metadata/global-metadata.dat"],
        ];
        // Tìm trong Frameworks/UnityFramework (Unity iOS để metadata cạnh đó).
        NSString *frameworksDir = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
        NSArray *fw = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksDir error:nil];
        NSMutableArray *allCandidates = [candidates mutableCopy];
        for (NSString *f in fw ?: @[]) {
            if ([f containsString:@"Unity"]) {
                [allCandidates addObject:[frameworksDir stringByAppendingPathComponent:[f stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"]]];
            }
        }
        // Tìm đệ quy nông trong bundle (tối đa 3 cấp).
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:NSBundle.mainBundle.bundlePath];
        int depthGuard = 0;
        for (NSString *p in en) {
            if (++depthGuard > 20000) break;
            if ([p.lastPathComponent isEqualToString:@"global-metadata.dat"]) {
                [allCandidates addObject:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:p]];
                break;
            }
        }
        for (NSString *c in allCandidates) {
            if ([fm fileExistsAtPath:c]) { metaPath = c; break; }
        }
        if (metaPath) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:metaPath error:nil];
            unsigned long long fsize = [attrs[NSFileSize] unsignedLongLongValue];
            [out appendFormat:@"# path: %@\n# size: %llu bytes\n", metaPath, fsize];
            NSData *head = [NSData dataWithContentsOfFile:metaPath options:NSDataReadingMappedIfSafe error:nil];
            if (head.length >= 64) {
                const uint32_t *u32 = (const uint32_t *)head.bytes;
                uint32_t sanity = u32[0], version = u32[1];
                [out appendFormat:@"# sanity: 0x%x (mong doi 0xfab11baf)\n# metadata version: %u\n", sanity, version];
                [out appendFormat:@"# stringLiteralCount: %u, stringCount: %u\n", u32[3], u32[7]];
                [out appendFormat:@"# (dung file nay + binary UnityFramework voi Il2CppDumper de ra dump.cs day du)\n"];
            } else {
                [out appendFormat:@"# khong doc duoc header\n"];
            }
        } else {
            [out appendFormat:@"# khong tim thay global-metadata.dat (khong phai app Unity hoac metadata o cho khac)\n"];
        }

        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [docs stringByAppendingPathComponent:@"ZheeOffsets.txt"];
        NSError *err = nil;
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) NSLog(@"[ZheeOffsetDump] write failed: %@", err);
        else NSLog(@"[ZheeOffsetDump] wrote %@ (%lu bytes)", path, (unsigned long)out.length);
    }
}

static int gAttempts = 0;

__attribute__((constructor)) static void ZheeOffsetDumpInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        @try {
            for (int i = 0; i < 5; i++) {
                ZheeDumpOffsets();
                gAttempts++;
                if (gIl2CppDone) break;
                // il2cpp chưa sẵn -> đợi 2s rồi dump lại (ghi đè file).
                [NSThread sleepForTimeInterval:2.0];
            }
        } @catch (NSException *e) {
            NSLog(@"[ZheeOffsetDump] exception: %@", e);
        }
    });
}
