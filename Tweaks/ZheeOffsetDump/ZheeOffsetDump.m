// ZheeOffsetDump.m v4 — Dylib dump offset: panel 3 tab + lg live + xuất dump.cs.
//
// Inject vào app bất kỳ (LC_LOAD_DYLIB). Mở app -> hiện panel -> tự chạy
// dump, lg chạy live trong panel -> xong tự xuất file ra Documents:
//   - dump.cs          (il2cpp, kiểu Il2CppDumper: namespace -> class ->
//                       field offset + method RVA)
//   - ZheeOffsets.txt  (image/framework, ObjC theo image, Mach-O symbols,
//                       metadata global-metadata.dat)
//   - global-metadata.dat + UnityFramework (file gốc cho Il2CppDumper)
//
// Panel 3 tab: Dump (lg + tiến trình) | Cài đặt (toggle từng phần,
// Full offset, kích thước panel) | About (tác giả + info app).
// Xoay ngang/dọc tự dựng lại panel. Chạy trên mọi app (không hardcode bundle).
//
// Không hook, không sửa gì trong app — chỉ đọc runtime.
// Nút nổi logo Z (kéo thả) để mở/đóng panel. Panel kéo được bằng thanh tiêu đề.
// Chạm vùng trống panel không ảnh hưởng app (cửa sổ pass-through).
//
// Build: xcrun -sdk iphoneos clang -arch arm64 -dynamiclib -fobjc-arc
//        -isysroot $(xcrun --sdk iphoneos --show-sdk-path)
//        -miphoneos-version-min=14.0 -framework Foundation -framework UIKit
//        -framework CoreGraphics -framework QuartzCore
//        -o ZheeOffsetDump.dylib ZheeOffsetDump.m

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdarg.h>
#import <string.h>
#import <sys/sysctl.h>
#import <unistd.h>

// --- String obfuscation: cac dinh danh nhay cam luu duoi dang XOR, giai ma luc chay ---
static char g_dB[256];
static const char *zChr(const unsigned char *enc, size_t len) {
    if (len >= sizeof(g_dB)) return "";
    for (size_t i = 0; i < len; i++) g_dB[i] = (char)(enc[i] ^ 0x5A ^ (unsigned char)(i & 0x07));
    g_dB[len] = 0;
    return g_dB;
}
static NSString *zStr(const unsigned char *enc, size_t len) {
    return [NSString stringWithUTF8String:zChr(enc, len)];
}
static BOOL zDA(void) {
    int mib[4] = {1, 14, 1, getpid()}; // {CTL_KERN, KERN_INFO, KERN_INFO_PROC, pid} (so, SDK iOS khong khai bao ten)
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return NO;
    return (info.kp_proc.p_flag & 0x00000800) != 0; // P_TRACED
}
static const unsigned char kS00[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x39, 0x35, 0x36, 0x39, 0x30, 0x30, 0x00, 0x3b, 0x38, 0x2e};
static const unsigned char kS01[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x39, 0x35, 0x36, 0x39, 0x30, 0x30, 0x00, 0x3b, 0x38, 0x2e, 0x04, 0x39, 0x2a, 0x2d, 0x3a, 0x31, 0x3f, 0x36, 0x32, 0x3d, 0x2a};
static const unsigned char kS02[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3c, 0x29, 0x28, 0x3d, 0x34, 0x3c, 0x33, 0x25, 0x02, 0x3d, 0x3e, 0x2c, 0x06, 0x37, 0x32, 0x3d, 0x3a, 0x3f};
static const unsigned char kS03[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x34, 0x37, 0x3a, 0x3f, 0x3c, 0x01, 0x38, 0x39, 0x29, 0x05, 0x35, 0x39, 0x34, 0x3b};
static const unsigned char kS04[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x34, 0x37, 0x3a, 0x3f, 0x3c, 0x01, 0x38, 0x39, 0x29, 0x05, 0x38, 0x34, 0x38, 0x2d, 0x2c, 0x03, 0x3e, 0x35, 0x2e, 0x36, 0x2d};
static const unsigned char kS05[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x34, 0x37, 0x3a, 0x3f, 0x3c, 0x01, 0x38, 0x39, 0x29, 0x05, 0x38, 0x34, 0x38, 0x2d, 0x2c};
static const unsigned char kS06[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3e, 0x36, 0x3a, 0x2b, 0x2a, 0x01, 0x38, 0x39, 0x29, 0x05, 0x36, 0x3d, 0x2d, 0x36, 0x30, 0x38, 0x2e};
static const unsigned char kS07[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3e, 0x36, 0x3a, 0x2b, 0x2a, 0x01, 0x38, 0x39, 0x29, 0x05, 0x3d, 0x31, 0x3c, 0x32, 0x3b, 0x2f};
static const unsigned char kS08[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3e, 0x36, 0x3a, 0x2b, 0x2a, 0x01, 0x38, 0x39, 0x29, 0x05, 0x35, 0x39, 0x34, 0x3b};
static const unsigned char kS09[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3e, 0x36, 0x3a, 0x2b, 0x2a, 0x01, 0x38, 0x39, 0x29, 0x05, 0x35, 0x39, 0x34, 0x3b, 0x2c, 0x2c, 0x3c, 0x39, 0x3e};
static const unsigned char kS10[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x30, 0x3f, 0x2f, 0x30, 0x36, 0x3a, 0x00, 0x3b, 0x38, 0x2e, 0x04, 0x36, 0x38, 0x33, 0x3a};
static const unsigned char kS11[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x30, 0x3f, 0x2f, 0x30, 0x36, 0x3a, 0x00, 0x3b, 0x38, 0x2e, 0x04, 0x2a, 0x3c, 0x2a, 0x2a, 0x2e, 0x33, 0x05, 0x2f, 0x21, 0x29, 0x3b};
static const unsigned char kS12[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x30, 0x3f, 0x2f, 0x30, 0x36, 0x3a, 0x00, 0x3b, 0x38, 0x2e, 0x04, 0x28, 0x38, 0x2c, 0x3e, 0x31, 0x02, 0x39, 0x34, 0x2d, 0x37, 0x2a};
static const unsigned char kS13[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x30, 0x3f, 0x2f, 0x30, 0x36, 0x3a, 0x00, 0x3b, 0x38, 0x2e, 0x04, 0x28, 0x38, 0x2c, 0x3e, 0x31};
static const unsigned char kS14[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x30, 0x3f, 0x2f, 0x30, 0x36, 0x3a, 0x00, 0x3b, 0x38, 0x2e, 0x04, 0x28, 0x38, 0x2c, 0x3e, 0x31, 0x02, 0x34, 0x3a, 0x35, 0x3c};
static const unsigned char kS15[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3b, 0x33, 0x3e, 0x34, 0x3d, 0x01, 0x38, 0x39, 0x29, 0x05, 0x35, 0x39, 0x34, 0x3b};
static const unsigned char kS16[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3b, 0x33, 0x3e, 0x34, 0x3d, 0x01, 0x38, 0x39, 0x29, 0x05, 0x34, 0x3e, 0x3f, 0x2d, 0x3a, 0x28};
static const unsigned char kS17[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3b, 0x33, 0x3e, 0x34, 0x3d, 0x01, 0x38, 0x39, 0x29, 0x05, 0x2f, 0x21, 0x29, 0x3b};
static const unsigned char kS18[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x29, 0x23, 0x2b, 0x3d, 0x06, 0x39, 0x3a, 0x28, 0x02, 0x34, 0x3a, 0x35, 0x3c};
static const unsigned char kS19[] = {0x33, 0x37, 0x6a, 0x3a, 0x2e, 0x2f, 0x03, 0x3b, 0x28, 0x3e, 0x3d};
static const unsigned char kS20[] = {0x3e, 0x2e, 0x35, 0x29, 0x70, 0x3c, 0x2f};
static const unsigned char kS21[] = {0x00, 0x33, 0x3d, 0x3c, 0x11, 0x39, 0x3a, 0x2e, 0x3f, 0x2f, 0x2b, 0x77, 0x2a, 0x27, 0x28};
static const unsigned char kS22[] = {0x3d, 0x37, 0x37, 0x3b, 0x3f, 0x33, 0x71, 0x30, 0x3f, 0x2f, 0x39, 0x3d, 0x3f, 0x2b, 0x3d, 0x73, 0x3e, 0x3a, 0x2c};
static const unsigned char kS23[] = {0x0f, 0x35, 0x31, 0x2d, 0x27, 0x19, 0x2e, 0x3c, 0x37, 0x3e, 0x2f, 0x36, 0x2c, 0x34};
static const unsigned char kS24[] = {0x1e, 0x3a, 0x2c, 0x38, 0x71, 0x12, 0x3d, 0x33, 0x3b, 0x3c, 0x3d, 0x3d, 0x71, 0x12, 0x39, 0x29, 0x3b, 0x3f, 0x39, 0x2d, 0x3f, 0x70, 0x3b, 0x31, 0x35, 0x39, 0x39, 0x35, 0x73, 0x32, 0x39, 0x29, 0x3b, 0x3f, 0x39, 0x2d, 0x3f, 0x71, 0x38, 0x3c, 0x2e};
static const unsigned char kS25[] = {0x17, 0x3e, 0x2c, 0x38, 0x3a, 0x3e, 0x28, 0x3c, 0x75, 0x3c, 0x34, 0x36, 0x3c, 0x3e, 0x30, 0x70, 0x37, 0x3e, 0x2c, 0x38, 0x3a, 0x3e, 0x28, 0x3c, 0x74, 0x3f, 0x39, 0x2d};
static const unsigned char kS26[] = {0x0f, 0x35, 0x31, 0x2d, 0x27, 0x19, 0x2e, 0x3c, 0x37, 0x3e, 0x2f, 0x36, 0x2c, 0x34, 0x72, 0x3b, 0x28, 0x3a, 0x35, 0x3c, 0x29, 0x30, 0x2e, 0x36, 0x75, 0x0e, 0x36, 0x30, 0x2a, 0x26, 0x1a, 0x2f, 0x3b, 0x36, 0x3d, 0x2e, 0x31, 0x2d, 0x37};
static const unsigned char kS27[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x3a, 0x2d, 0x2d, 0x31};
static const unsigned char kS28[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x34, 0x3a, 0x33, 0x3d};
static const unsigned char kS29[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x28, 0x21, 0x34};
static const unsigned char kS30[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x32, 0x34, 0x6b, 0x3d, 0x2f, 0x2c};
static const unsigned char kS31[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x3e, 0x20, 0x29, 0x31, 0x2d, 0x28, 0x2f, 0x3b, 0x2c};
static const unsigned char kS32[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x3d, 0x2d, 0x35, 0x32};
static const unsigned char kS33[] = {0x20, 0x33, 0x3d, 0x3c, 0x3a, 0x2a, 0x31, 0x2d, 0x74, 0x28, 0x31, 0x23, 0x3b};

// ---------------------------------------------------------------------------
// il2cpp API (opaque types, dlsym lúc runtime)
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
typedef const char *(*FnMethodParamName)(const MethodInfo *, uint32_t);
typedef const char *(*FnFieldName)(const FieldInfo *);
typedef size_t (*FnFieldOffset)(const FieldInfo *);
typedef const Il2CppType *(*FnFieldType)(const FieldInfo *);
typedef char *(*FnTypeName)(const Il2CppType *);
typedef void (*FnFree)(void *);

static void *zSym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

// ---------------------------------------------------------------------------
// Image range
// ---------------------------------------------------------------------------
// Cache range cua image: tinh 1 lan moi lan dump, tim bang binary search.
// (Ban cu goi zIR cho MOI method -> quet lai 1342 image + parse
// header moi lan -> treo voi app lon nhu Free Fire.)
static uintptr_t *g_imgBase = NULL;
static uintptr_t *g_imgEnd = NULL;
static uint32_t *g_imgSorted = NULL; // index image, sap xep theo base tang dan
static uint32_t g_imgCacheCount = 0;

static int cmpImageBase(const void *a, const void *b) {
    uintptr_t ba = g_imgBase[*(const uint32_t *)a];
    uintptr_t bb = g_imgBase[*(const uint32_t *)b];
    if (ba < bb) return -1;
    if (ba > bb) return 1;
    return 0;
}

static BOOL *g_imgInBundle = NULL; // image thuoc app bundle? (ObjC chi dump may image nay)
static BOOL g_fullOffset = NO;     // full offset: dump ca system framework

static void zBBF(NSString *bundlePath, uint32_t count) {
    free(g_imgInBundle);
    g_imgInBundle = NULL;
    if (count == 0) return;
    g_imgInBundle = (BOOL *)malloc(sizeof(BOOL) * count);
    if (!g_imgInBundle) return;
    for (uint32_t i = 0; i < count; i++) {
        if (g_fullOffset) { g_imgInBundle[i] = YES; continue; }
        if (!bundlePath) { g_imgInBundle[i] = YES; continue; } // khong xac dinh duoc bundle -> giu het
        const char *n = _dyld_get_image_name(i);
        g_imgInBundle[i] = (n && [[NSString stringWithUTF8String:n] hasPrefix:bundlePath]) ? YES : NO;
    }
}

static BOOL zIRU(uint32_t idx, uintptr_t *outBase, uintptr_t *outEnd) {
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

static void zBIC(uint32_t count) {
    free(g_imgBase); free(g_imgEnd); free(g_imgSorted);
    g_imgBase = NULL; g_imgEnd = NULL; g_imgSorted = NULL; g_imgCacheCount = 0;
    if (count == 0) return;
    g_imgBase = (uintptr_t *)malloc(sizeof(uintptr_t) * count);
    g_imgEnd = (uintptr_t *)malloc(sizeof(uintptr_t) * count);
    g_imgSorted = (uint32_t *)malloc(sizeof(uint32_t) * count);
    if (!g_imgBase || !g_imgEnd || !g_imgSorted) {
        free(g_imgBase); free(g_imgEnd); free(g_imgSorted);
        g_imgBase = NULL; g_imgEnd = NULL; g_imgSorted = NULL;
        return;
    }
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t b = 0, e = 0;
        zIRU(i, &b, &e);
        g_imgBase[i] = b; g_imgEnd[i] = e; g_imgSorted[i] = i;
    }
    qsort(g_imgSorted, count, sizeof(uint32_t), cmpImageBase);
    g_imgCacheCount = count;
}

static BOOL zIR(uint32_t idx, uintptr_t *outBase, uintptr_t *outEnd) {
    if (idx < g_imgCacheCount && g_imgBase) {
        *outBase = g_imgBase[idx];
        *outEnd = g_imgEnd[idx];
        return YES;
    }
    return zIRU(idx, outBase, outEnd);
}

static int zIC(uintptr_t p, uint32_t count) {
    if (g_imgBase && count == g_imgCacheCount) {
        int lo = 0, hi = (int)g_imgCacheCount - 1, ans = -1;
        while (lo <= hi) {
            int mid = (lo + hi) / 2;
            uint32_t idx = g_imgSorted[mid];
            if (g_imgBase[idx] <= p) { ans = mid; lo = mid + 1; }
            else hi = mid - 1;
        }
        if (ans >= 0) {
            uint32_t idx = g_imgSorted[ans];
            if (p < g_imgEnd[idx]) return (int)idx;
        }
        return -1;
    }
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t b = 0, e = 0;
        if (zIRU(i, &b, &e) && p >= b && p < e) return (int)i;
    }
    return -1;
}

static int cCN(const void *a, const void *b) {
    return strcmp(class_getName(*(Class *)a) ?: "", class_getName(*(Class *)b) ?: "");
}
static int cMN(const void *a, const void *b) {
    return strcmp(sel_getName(method_getName(*(Method *)a)) ?: "",
                  sel_getName(method_getName(*(Method *)b)) ?: "");
}

// ---------------------------------------------------------------------------
// Panel + lg
// ---------------------------------------------------------------------------
@interface ZPW : UIWindow
@end
@implementation ZPW
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface ZDC : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIWindow *fW;
@property (nonatomic, strong) UIButton *fB;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *lV;
@property (nonatomic, strong) UILabel *sLbl;
@property (nonatomic, strong) UIButton *dBtn;
@property (nonatomic, strong) NSMutableArray<UIButton *> *sideButtons;
@property (nonatomic, strong) UIView *dTab;
@property (nonatomic, strong) UIView *sTab;
@property (nonatomic, strong) UIView *aTab;
@property (nonatomic, strong) UIProgressView *pBar;
@property (nonatomic, strong) NSDictionary *cfg; // cau hinh UI tai tu GitHub (panel.json)
@property (nonatomic, strong) UIView *updateAlert;
@property (nonatomic, assign) BOOL dmp;
@property (nonatomic, assign) BOOL dmpCancel;
@property (nonatomic, assign) BOOL iDone;
// Cai dat (luu UserDefaults, prefix zheedump.)
@property (nonatomic, assign) BOOL dE;   // tu dong dump khi mo app
@property (nonatomic, assign) BOOL dO;
@property (nonatomic, assign) BOOL dSy;
@property (nonatomic, assign) BOOL dI;
@property (nonatomic, assign) BOOL dER;
@property (nonatomic, assign) BOOL dFu;      // full offset: ca system framework
@property (nonatomic, assign) NSInteger sM; // 0 Nho, 1 Vua, 2 Lon, 3 Tuy chinh (keo goc)
@property (nonatomic, strong) NSMutableArray<UISwitch *> *allSwitches;
@property (nonatomic, assign) CGFloat customW;
@property (nonatomic, assign) CGFloat customH;
@end

@implementation ZDC

+ (instancetype)sh { static ZDC *s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [ZDC new]; }); return s; }

- (UIColor *)bB { return [self cfgColor:@"accentColor" def:[UIColor colorWithRed:0.11 green:0.63 blue:0.95 alpha:1]]; }
- (UIColor *)bC { return [UIColor colorWithRed:0.00 green:0.82 blue:1.00 alpha:1]; }

// Log live: ghi vào panel + NSLog.
- (void)lg:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ZDC] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.lV) return;
        NSString *line = [NSString stringWithFormat:@"%@\n", msg];
        self.lV.text = [self.lV.text stringByAppendingString:line];
        NSRange end = NSMakeRange(self.lV.text.length, 0);
        [self.lV scrollRangeToVisible:end];
    });
}

- (void)sS:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{ self.sLbl.text = s; });
}

- (void)sP:(float)p {
    dispatch_async(dispatch_get_main_queue(), ^{ self.pBar.progress = p; });
}

// ---------------------------------------------------------------------------
// Cai dat (UserDefaults) + logo ZheeSign + helpers UI
// ---------------------------------------------------------------------------
- (void)lS {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    // Mac dinh lay tu panel.json (GitHub) khi chua co gia tri da luu.
    self.dE = [d objectForKey:zStr(kS27, sizeof(kS27))] ? [d boolForKey:zStr(kS27, sizeof(kS27))] : [self cfgBool:@"autoDumpDefault" def:YES];
    self.dO = [d objectForKey:zStr(kS28, sizeof(kS28))] ? [d boolForKey:zStr(kS28, sizeof(kS28))] : [self cfgBool:@"dumpObjCDefault" def:YES];
    self.dSy = [d objectForKey:zStr(kS29, sizeof(kS29))] ? [d boolForKey:zStr(kS29, sizeof(kS29))] : [self cfgBool:@"dumpSymbolsDefault" def:YES];
    self.dI = [d objectForKey:zStr(kS30, sizeof(kS30))] ? [d boolForKey:zStr(kS30, sizeof(kS30))] : [self cfgBool:@"dumpIl2cppDefault" def:YES];
    self.dER = [d objectForKey:zStr(kS31, sizeof(kS31))] ? [d boolForKey:zStr(kS31, sizeof(kS31))] : [self cfgBool:@"exportRawDefault" def:YES];
    self.dFu = [d objectForKey:zStr(kS32, sizeof(kS32))] ? [d boolForKey:zStr(kS32, sizeof(kS32))] : [self cfgBool:@"fullOffsetDefault" def:NO];
    self.sM = [d objectForKey:zStr(kS33, sizeof(kS33))] ? [d integerForKey:zStr(kS33, sizeof(kS33))] : MIN(2, MAX(0, [self cfgInt:@"sizeDefault" def:1]));
    if (self.sM < 0 || self.sM > 3) self.sM = 1;
    self.customW = [d doubleForKey:@"zheedump.cw"];
    self.customH = [d doubleForKey:@"zheedump.ch"];
}

// ---- Cau hinh UI tu xa (panel.json tren GitHub) ----
- (NSString *)cfgStr:(NSString *)key def:(NSString *)def {
    id v = self.cfg[key];
    return [v isKindOfClass:[NSString class]] ? v : def;
}
- (BOOL)cfgBool:(NSString *)key def:(BOOL)def {
    id v = self.cfg[key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def;
}
- (NSInteger)cfgInt:(NSString *)key def:(NSInteger)def {
    id v = self.cfg[key];
    return [v isKindOfClass:[NSNumber class]] ? [v integerValue] : def;
}
- (UIColor *)cfgColor:(NSString *)key def:(UIColor *)def {
    NSString *s = [self cfgStr:key def:nil];
    if (!s) return def;
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6) return def;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return def;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}
- (void)loadCfgCache {
    NSData *data = [NSData dataWithContentsOfFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"zhee-panel.json"]];
    if (!data) return;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]]) self.cfg = obj;
}
- (void)fetchCfg {
    NSDictionary *oldCfg = self.cfg ?: @{};
    BOOL hadCache = (self.cfg != nil);
    NSString *urlStr = [NSString stringWithFormat:@"https://raw.githubusercontent.com/zheedevVn/XzheeTool/main/Tweaks/ZheeOffsetDump/panel.json?t=%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
    conf.timeoutIntervalForRequest = 5;
    NSURLSession *sess = [NSURLSession sessionWithConfiguration:conf];
    [[sess dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data || err) return;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        NSData *oldData = [NSJSONSerialization dataWithJSONObject:oldCfg options:0 error:nil];
        NSData *newData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
        if ([oldData isEqualToData:newData]) return; // khong doi -> im lang, khong lam gi
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"zhee-panel.json"] atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.cfg = obj;
            if (!hadCache) {
                // Lan dau: ap dung im lang, khong thong bao, khong thoat app.
                if (!self.panel.hidden) [self rP];
            } else {
                // Co phien ban giao dien moi: alert 5s roi tu thoat app, mo lai thay giao dien moi.
                [self showUpdateAlert];
            }
        });
    }] resume];
}

// Alert thong bao cap nhat giao dien: kinh mo sang giua man hinh,
// avatar + vong xoay, thanh tien trinh gradient 5s, rung may 1 cai, roi tu thoat app.
- (void)showUpdateAlert {
    if (self.updateAlert) return;
    // Rung may 1 cai (lay AudioServicesPlaySystemSound qua dlsym, khoi them framework).
    static void (*vibFn)(unsigned int) = NULL;
    static dispatch_once_t vibOnce;
    dispatch_once(&vibOnce, ^{
        void *h = dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_NOW);
        if (h) vibFn = (void (*)(unsigned int))dlsym(h, "AudioServicesPlaySystemSound");
    });
    if (vibFn) vibFn(4095); // kSystemSoundID_Vibrate
    CGFloat w = MIN(320, self.fW.bounds.size.width - 48);
    CGFloat h = 190;
    CGRect fb = self.fW.bounds;
    UIView *alert = [[UIView alloc] initWithFrame:CGRectMake((fb.size.width - w) / 2, (fb.size.height - h) / 2, w, h)];
    alert.userInteractionEnabled = NO;
    alert.layer.shadowColor = UIColor.blackColor.CGColor;
    alert.layer.shadowOpacity = 0.25; alert.layer.shadowRadius = 16; alert.layer.shadowOffset = CGSizeMake(0, 8);
    UIView *body = [[UIView alloc] initWithFrame:alert.bounds];
    body.layer.cornerRadius = 20;
    body.clipsToBounds = YES;
    body.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.5].CGColor;
    body.layer.borderWidth = 1;
    [alert addSubview:body];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
    blur.frame = body.bounds;
    [body addSubview:blur];
    UIView *dim = [[UIView alloc] initWithFrame:body.bounds];
    dim.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    [body addSubview:dim];
    // Avatar + vong xoay.
    CGFloat ax = (w - 64) / 2;
    UIView *avatarBox = [[UIView alloc] initWithFrame:CGRectMake(ax, 18, 64, 64)];
    avatarBox.layer.cornerRadius = 32;
    avatarBox.clipsToBounds = YES;
    avatarBox.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.08];
    NSData *avData = [NSData dataWithContentsOfFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"zhee-avatar.png"]];
    UIImage *avImg = avData ? [UIImage imageWithData:avData] : nil;
    if (avImg) {
        UIImageView *av = [[UIImageView alloc] initWithImage:avImg];
        av.frame = avatarBox.bounds;
        av.contentMode = UIViewContentModeScaleAspectFill;
        [avatarBox addSubview:av];
    } else {
        [avatarBox addSubview:[self zL:64]];
    }
    [body addSubview:avatarBox];
    UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(ax - 4, 14, 72, 72)];
    ring.backgroundColor = UIColor.clearColor;
    CAShapeLayer *arc = [CAShapeLayer layer];
    arc.frame = ring.bounds;
    arc.fillColor = UIColor.clearColor.CGColor;
    arc.strokeColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1].CGColor;
    arc.lineWidth = 3;
    arc.lineCap = kCALineCapRound;
    arc.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(36, 36) radius:33 startAngle:-M_PI_2 endAngle:-M_PI_2 + M_PI * 1.2 clockwise:YES].CGPath;
    [ring.layer addSublayer:arc];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @(0); spin.toValue = @(M_PI * 2); spin.duration = 1.2; spin.repeatCount = HUGE_VALF;
    [ring.layer addAnimation:spin forKey:@"spin"];
    [body addSubview:ring];
    // Tieu de + phu de.
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 94, w - 32, 24)];
    title.text = @"Đang cập nhật giao diện…";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textColor = [UIColor colorWithWhite:0.08 alpha:1];
    title.textAlignment = NSTextAlignmentCenter;
    [body addSubview:title];
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 120, w - 32, 18)];
    sub.text = @"Vui lòng đợi…";
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor colorWithWhite:0.35 alpha:1];
    sub.textAlignment = NSTextAlignmentCenter;
    [body addSubview:sub];
    // Thanh tien trinh gradient (chay 0 -> 100% trong 5s).
    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(20, h - 24, w - 40, 6)];
    track.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.12];
    track.layer.cornerRadius = 3;
    track.clipsToBounds = YES;
    [body addSubview:track];
    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 6)];
    fill.clipsToBounds = YES;
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = CGRectMake(0, 0, w - 40, 6);
    grad.colors = @[(id)[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1].CGColor,
                    (id)[UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1].CGColor,
                    (id)[UIColor colorWithRed:0.6 green:0.3 blue:1.0 alpha:1].CGColor];
    grad.startPoint = CGPointMake(0, 0.5); grad.endPoint = CGPointMake(1, 0.5);
    [fill.layer addSublayer:grad];
    [track addSubview:fill];
    self.updateAlert = alert;
    [self.fW addSubview:alert];
    alert.alpha = 0;
    alert.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        alert.alpha = 1;
        alert.transform = CGAffineTransformIdentity;
    } completion:nil];
    [UIView animateWithDuration:5 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        fill.frame = CGRectMake(0, 0, w - 40, 6);
    } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0); // thoat app, mo lai la thay giao dien moi
    });
}

- (void)sSv {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:self.dE forKey:zStr(kS27, sizeof(kS27))];
    [d setBool:self.dO forKey:zStr(kS28, sizeof(kS28))];
    [d setBool:self.dSy forKey:zStr(kS29, sizeof(kS29))];
    [d setBool:self.dI forKey:zStr(kS30, sizeof(kS30))];
    [d setBool:self.dER forKey:zStr(kS31, sizeof(kS31))];
    [d setBool:self.dFu forKey:zStr(kS32, sizeof(kS32))];
    [d setInteger:self.sM forKey:zStr(kS33, sizeof(kS33))];
    [d setDouble:self.customW forKey:@"zheedump.cw"];
    [d setDouble:self.customH forKey:@"zheedump.ch"];
}

// Logo ZheeSign: chu Z neon (cyan -> tim -> hong) tren nen toi.
- (UIView *)zL:(CGFloat)s {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s, s)];
    CATextLayer *text = [CATextLayer layer];
    text.string = @"Z";
    text.font = (__bridge CFTypeRef _Nullable)(@"ArialRoundedMTBold");
    text.fontSize = s * 0.82;
    text.alignmentMode = kCAAlignmentCenter;
    text.frame = CGRectMake(0, -s * 0.06, s, s);
    text.contentsScale = UIScreen.mainScreen.scale;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = v.bounds;
    g.colors = @[(__bridge id)[UIColor colorWithRed:0.00 green:0.85 blue:1.00 alpha:1].CGColor,
                 (__bridge id)[UIColor colorWithRed:0.55 green:0.30 blue:1.00 alpha:1].CGColor,
                 (__bridge id)[UIColor colorWithRed:1.00 green:0.30 blue:0.60 alpha:1].CGColor];
    g.startPoint = CGPointMake(0, 0); g.endPoint = CGPointMake(1, 1);
    g.mask = text;
    [v.layer addSublayer:g];
    return v;
}

- (CGSize)pS:(NSInteger)mode screen:(CGRect)screen {
    if (mode == 3) return CGSizeMake(MIN(MAX(self.customW, 260), screen.size.width - 16),
                                    MIN(MAX(self.customH, 320), screen.size.height - 32));
    if (mode == 0) return CGSizeMake(screen.size.width - 64, screen.size.height - 120);
    if (mode == 2) return CGSizeMake(screen.size.width - 16, screen.size.height - 32);
    return CGSizeMake(screen.size.width - 32, screen.size.height - 64);
}

- (void)st {
    @try {
        if (zDA()) return; // debugger dinh kem -> khong chay
        [self loadCfgCache]; // cau hinh UI da cache tu lan mo truoc
        [self lS];
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
        }
        if (!scene) { for (UIScene *s in UIApplication.sharedApplication.connectedScenes) { if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; } } }

        CGRect screen = UIScreen.mainScreen.bounds;
        CGFloat size = 56;
        self.fW = scene ? [[ZPW alloc] initWithWindowScene:scene] : [[ZPW alloc] initWithFrame:screen];
        self.fW.frame = screen;
        self.fW.windowLevel = UIWindowLevelAlert + 1;
        self.fW.backgroundColor = UIColor.clearColor;
        // Host VC trong suot de present UIDocumentPicker (view tat tuong tac -> cham xuyen).
        UIViewController *host = [UIViewController new];
        host.view.userInteractionEnabled = NO;
        self.fW.rootViewController = host;

        self.fB = [UIButton buttonWithType:UIButtonTypeCustom];
        self.fB.frame = CGRectMake(screen.size.width - size - 16, screen.size.height / 2 - size / 2, size, size);
        self.fB.layer.cornerRadius = size / 2;
        self.fB.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.09 alpha:1];
        self.fB.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.25].CGColor;
        self.fB.layer.borderWidth = 1;
        self.fB.layer.shadowColor = UIColor.blackColor.CGColor;
        self.fB.layer.shadowOpacity = 0.45; self.fB.layer.shadowRadius = 10;
        self.fB.layer.shadowOffset = CGSizeMake(0, 4);
        UIView *logo = [self zL:size * 0.62];
        logo.center = CGPointMake(size / 2, size / 2);
        logo.userInteractionEnabled = NO;
        [self.fB addSubview:logo];
        [self.fB addTarget:self action:@selector(tP) forControlEvents:UIControlEventTouchUpInside];
        [self.fB addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dFl:)]];
        [self.fW addSubview:self.fB];

        [self bP];
        self.fW.hidden = NO;
        [self fetchCfg]; // lay panel.json moi nhat tren GitHub, co thay doi thi dung lai panel
        // Xoay ngang/doc: dung lai panel + keo nut noi vao trong man hinh.
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hO)
                                                     name:UIDeviceOrientationDidChangeNotification object:nil];
        // Mo panel ngay + chay dump neu bat tu dong.
        if (self.dE) [self sD];
        else [self lg:@"Tự động dump: TẮT (bật trong tab Cài đặt)"];
    } @catch (NSException *e) {}
}

- (void)hO {
    UIDeviceOrientation o = UIDevice.currentDevice.orientation;
    if (o != UIDeviceOrientationPortrait && o != UIDeviceOrientationLandscapeLeft &&
        o != UIDeviceOrientationLandscapeRight && o != UIDeviceOrientationPortraitUpsideDown) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat r = 28;
        CGPoint c = self.fB.center;
        c.x = MAX(r, MIN(b.size.width - r, c.x));
        c.y = MAX(r + 40, MIN(b.size.height - r - 40, c.y));
        self.fB.center = c;
        [self rP];
    });
}

// Dung lai panel (giữ lg + tab) — dung khi doi kich thuoc / xoay man hinh.
- (void)rP {
    NSString *savedLog = self.lV.text ?: @"";
    NSInteger savedTab = self.dTab.hidden ? (self.sTab.hidden ? 2 : 1) : 0;
    BOOL wasHidden = self.panel.hidden;
    [self.panel removeFromSuperview];
    self.panel = nil;
    [self bP];
    self.panel.hidden = wasHidden;
    self.lV.text = savedLog;
    NSRange end = NSMakeRange(self.lV.text.length, 0);
    [self.lV scrollRangeToVisible:end];
    [self sideTap:self.sideButtons[savedTab]];
}

- (void)dFl:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.fW];
    CGPoint c = self.fB.center;
    c.x += t.x; c.y += t.y;
    CGRect b = self.fW.bounds;
    CGFloat r = 28;
    c.x = MAX(r, MIN(b.size.width - r, c.x));
    c.y = MAX(r + 40, MIN(b.size.height - r - 40, c.y));
    self.fB.center = c;
    [pan setTranslation:CGPointZero inView:self.fW];
}

- (void)bP {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGSize sz = [self pS:self.sM screen:screen];
    CGFloat w = sz.width, h = sz.height;
    self.allSwitches = [NSMutableArray array];
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2, (screen.size.height - h) / 2, w, h)];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.4; self.panel.layer.shadowRadius = 20;
    self.panel.layer.shadowOffset = CGSizeMake(0, 10);
    self.panel.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.18].CGColor;
    self.panel.layer.borderWidth = 1;
    self.panel.clipsToBounds = YES;
    [self.fW addSubview:self.panel];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = self.panel.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:blur];

    // Lop nen gan duc (panel mau sac, khong bi game phia sau lam duc mau).
    UIView *dim = [[UIView alloc] initWithFrame:self.panel.bounds];
    dim.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.96];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:dim];

    // Thanh tiêu đề = tay cầm kéo panel.
    CGFloat pad = 16;
    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 48)];
    [self.panel addSubview:handle];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dPn:)];
    panelPan.delegate = self;
    [handle addGestureRecognizer:panelPan];

    UIView *miniLogo = [self zL:26];
    miniLogo.frame = CGRectMake(pad, 11, 26, 26);
    miniLogo.userInteractionEnabled = NO;
    [handle addSubview:miniLogo];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, w, 24)];
    title.text = [self cfgStr:@"title" def:@"Zhee Dump"]; title.font = [UIFont boldSystemFontOfSize:19]; title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [handle addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w - 40, 10, 28, 28);
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.7];
    [close addTarget:self action:@selector(tP) forControlEvents:UIControlEventTouchUpInside];
    [handle addSubview:close];

    // Sidebar trai (kieu menu mod): Dump | Cai dat | About + brand duoi cung.
    CGFloat sidebarW = (w < 500) ? 120 : 150;
    CGFloat cw = w - sidebarW - 24;
    UIView *side = [[UIView alloc] initWithFrame:CGRectMake(12, 90, sidebarW, h - 90 - 12)];
    side.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    side.layer.cornerRadius = 14;
    [self.panel addSubview:side];
    self.sideButtons = [NSMutableArray array];
    NSArray *sideTitles = @[@"Dump", @"Cài đặt", @"About"];
    NSArray *sideIcons = @[@"arrow.down.to.line", @"gearshape", @"info.circle"];
    CGFloat sideH = side.bounds.size.height;
    // Nut sidebar tu co gian theo chieu cao panel (panel thap -> nut nho lai, khong de brand).
    CGFloat btnH = MIN(52, MAX(36, (sideH - 42 - 16) / 3));
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(8, 8 + i * (btnH + 8), sidebarW - 16, btnH);
        b.layer.cornerRadius = 12;
        b.tag = i;
        [b addTarget:self action:@selector(sideTap:) forControlEvents:UIControlEventTouchUpInside];
        // Icon outline SF Symbols (co san cua Apple, khong tu ve) + nhan ben duoi.
        CGFloat imgSize = (btnH >= 48) ? 22 : 18;
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:sideIcons[i]]];
        icon.tintColor = UIColor.whiteColor;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.frame = CGRectMake((sidebarW - 16 - imgSize) / 2, btnH - 14 - imgSize - 2, imgSize, imgSize);
        icon.userInteractionEnabled = NO;
        [b addSubview:icon];
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, btnH - 16, sidebarW - 16, 14)];
        lbl.text = sideTitles[i];
        lbl.font = [UIFont boldSystemFontOfSize:12];
        lbl.textColor = UIColor.whiteColor;
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.userInteractionEnabled = NO;
        [b addSubview:lbl];
        [side addSubview:b];
        [self.sideButtons addObject:b];
    }
    UILabel *brand = [[UILabel alloc] initWithFrame:CGRectMake(0, sideH - 26, sidebarW, 22)];
    brand.text = [self cfgStr:@"brand" def:@"Zhee Dev"]; brand.font = [UIFont boldSystemFontOfSize:14];
    brand.textColor = [self cfgColor:@"brandColor" def:[UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1]];
    brand.textAlignment = NSTextAlignmentCenter;
    brand.hidden = (sideH - 26 < 8 + 3 * (btnH + 8) + 8);
    [side addSubview:brand];
    [self updateSideButtons];

    CGFloat contentY = 90;
    CGFloat contentH = h - contentY - 12;
    CGFloat contentX = sidebarW + 12;

    // ---- Tab Dump ----
    self.dTab = [[UIView alloc] initWithFrame:CGRectMake(contentX, contentY, cw, contentH)];
    BOOL wide = (cw >= 420);
    CGFloat quickH = wide ? 40 : 72;
    CGFloat bottomY = contentH - 38;
    CGFloat row1Y = wide ? bottomY : bottomY - 8 - 38;
    CGFloat exportY = bottomY;
    CGFloat statusY = row1Y - 8 - 20;
    CGFloat progY = statusY - 6 - 4;
    CGFloat logY = quickH + 8;
    CGFloat logH = progY - 8 - logY;
    // Hang toggle nhanh: rong = 1 hang 2 toggle, hep = xep doc (dong bo voi tab Cai dat).
    UIView *quickRow = [[UIView alloc] initWithFrame:CGRectMake(pad, 0, cw - pad * 2, quickH)];
    quickRow.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    quickRow.layer.cornerRadius = 12;
    UISwitch *qAuto = [UISwitch new];
    qAuto.on = self.dE; qAuto.tag = 1;
    qAuto.onTintColor = [UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1];
    [qAuto addTarget:self action:@selector(sC:) forControlEvents:UIControlEventValueChanged];
    UISwitch *qFull = [UISwitch new];
    qFull.on = self.dFu; qFull.tag = 6;
    qFull.onTintColor = [UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1];
    [qFull addTarget:self action:@selector(sC:) forControlEvents:UIControlEventValueChanged];
    if (wide) {
        CGFloat half = (cw - pad * 2) / 2;
        UILabel *qAutoLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 110, 20)];
        qAutoLbl.text = @"Tự động Dump"; qAutoLbl.font = [UIFont boldSystemFontOfSize:14]; qAutoLbl.textColor = UIColor.whiteColor;
        [quickRow addSubview:qAutoLbl];
        qAuto.frame = CGRectMake(126, 5, 51, 31);
        [quickRow addSubview:qAuto];
        UILabel *qFullLbl = [[UILabel alloc] initWithFrame:CGRectMake(half + 12, 10, 110, 20)];
        qFullLbl.text = @"Full offset"; qFullLbl.font = [UIFont boldSystemFontOfSize:14]; qFullLbl.textColor = UIColor.whiteColor;
        [quickRow addSubview:qFullLbl];
        qFull.frame = CGRectMake(half + 126, 5, 51, 31);
        [quickRow addSubview:qFull];
    } else {
        UILabel *qAutoLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 140, 20)];
        qAutoLbl.text = @"Tự động Dump"; qAutoLbl.font = [UIFont boldSystemFontOfSize:14]; qAutoLbl.textColor = UIColor.whiteColor;
        [quickRow addSubview:qAutoLbl];
        qAuto.frame = CGRectMake(cw - pad * 2 - 51 - 12, 4, 51, 31);
        [quickRow addSubview:qAuto];
        UIView *qDiv = [[UIView alloc] initWithFrame:CGRectMake(12, 36, cw - pad * 2 - 24, 1)];
        qDiv.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.1];
        [quickRow addSubview:qDiv];
        UILabel *qFullLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 44, 140, 20)];
        qFullLbl.text = @"Full offset"; qFullLbl.font = [UIFont boldSystemFontOfSize:14]; qFullLbl.textColor = UIColor.whiteColor;
        [quickRow addSubview:qFullLbl];
        qFull.frame = CGRectMake(cw - pad * 2 - 51 - 12, 40, 51, 31);
        [quickRow addSubview:qFull];
    }
    [self.allSwitches addObject:qAuto];
    [self.allSwitches addObject:qFull];
    [self.dTab addSubview:quickRow];
    self.lV = [[UITextView alloc] initWithFrame:CGRectMake(pad, logY, cw - pad * 2, logH)];
    self.lV.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.35];
    self.lV.layer.cornerRadius = 14;
    self.lV.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.12].CGColor;
    self.lV.layer.borderWidth = 1;
    self.lV.textColor = [self cfgColor:@"logTextColor" def:[UIColor colorWithRed:0.7 green:1.0 blue:0.7 alpha:1]];
    self.lV.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.lV.editable = NO;
    self.lV.selectable = YES;
    self.lV.text = @"";
    [self.dTab addSubview:self.lV];

    self.pBar = [[UIProgressView alloc] initWithFrame:CGRectMake(pad, progY, cw - pad * 2, 4)];
    self.pBar.progressTintColor = self.bC;
    self.pBar.trackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
    self.pBar.progress = 0;
    [self.dTab addSubview:self.pBar];

    self.sLbl = [[UILabel alloc] initWithFrame:CGRectMake(pad, statusY, cw - pad * 2, 20)];
    self.sLbl.font = [UIFont systemFontOfSize:13];
    self.sLbl.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.8];
    self.sLbl.textAlignment = NSTextAlignmentCenter;
    self.sLbl.text = @"Đang chạy…";
    [self.dTab addSubview:self.sLbl];

    self.dBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dBtn.layer.cornerRadius = 12;
    self.dBtn.backgroundColor = [self cfgColor:@"dumpButtonColor" def:[UIColor colorWithRed:0.18 green:0.48 blue:1.0 alpha:1]];
    [self.dBtn setTitle:[self cfgStr:@"dumpButtonTitle" def:@"Dump lại"] forState:UIControlStateNormal];
    self.dBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.dBtn setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    self.dBtn.tintColor = UIColor.whiteColor;
    self.dBtn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    self.dBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    [self.dBtn addTarget:self action:@selector(dA) forControlEvents:UIControlEventTouchUpInside];
    [self.dTab addSubview:self.dBtn];

    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    deleteButton.layer.cornerRadius = 12;
    deleteButton.backgroundColor = [self cfgColor:@"deleteButtonColor" def:[UIColor colorWithRed:0.9 green:0.28 blue:0.3 alpha:1]];
    [deleteButton setTitle:[self cfgStr:@"deleteButtonTitle" def:@"Xóa file"] forState:UIControlStateNormal];
    deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    deleteButton.tintColor = UIColor.whiteColor;
    deleteButton.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    deleteButton.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    [deleteButton addTarget:self action:@selector(dF) forControlEvents:UIControlEventTouchUpInside];
    [self.dTab addSubview:deleteButton];

    UIButton *exportButton = [UIButton buttonWithType:UIButtonTypeCustom];
    exportButton.layer.cornerRadius = 12;
    exportButton.backgroundColor = [self cfgColor:@"exportButtonColor" def:[UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1]];
    [exportButton setTitle:[self cfgStr:@"exportButtonTitle" def:@"Xuất ra Tải về"] forState:UIControlStateNormal];
    exportButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [exportButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    exportButton.tintColor = UIColor.whiteColor;
    exportButton.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    exportButton.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    [exportButton addTarget:self action:@selector(eF) forControlEvents:UIControlEventTouchUpInside];
    [self.dTab addSubview:exportButton];
    if (wide) {
        // Rong: 1 hang 3 nut.
        CGFloat bw3 = (cw - pad * 2 - 16) / 3;
        self.dBtn.frame = CGRectMake(pad, row1Y, bw3, 38);
        deleteButton.frame = CGRectMake(pad + bw3 + 8, row1Y, bw3, 38);
        exportButton.frame = CGRectMake(pad + 2 * bw3 + 16, row1Y, bw3, 38);
    } else {
        // Hep: 2 hang (2 + 1).
        CGFloat bw = (cw - pad * 2 - 8) / 2;
        self.dBtn.frame = CGRectMake(pad, row1Y, bw, 38);
        deleteButton.frame = CGRectMake(pad + bw + 8, row1Y, bw, 38);
        exportButton.frame = CGRectMake(pad, exportY, cw - pad * 2, 38);
    }
    [self.panel addSubview:self.dTab];

    // ---- Tab Cài đặt ----
    self.sTab = [[UIView alloc] initWithFrame:CGRectMake(contentX, contentY, cw, contentH)];
    self.sTab.hidden = YES;
    UIScrollView *setScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, cw, contentH)];
    // Dan hang toggle de lap day panel (panel cao -> hang cao hon + can giua).
    CGFloat fill = 1.0;
    if (contentH > 486) fill = MIN(1.4, (contentH - 114) / 372.0);
    CGFloat rowH = 54 * fill;
    CGFloat totalH = 6 * (rowH + 8) + 66 + 48;
    CGFloat sy = (totalH < contentH) ? (contentH - totalH) / 2 : 0;
    NSArray *toggles = @[
        @[@"Tự động Dump", @"Chạy dump ngay khi mở app", @(self.dE), @1],
        @[@"Dump ObjC", @"Class / method ObjC theo image", @(self.dO), @2],
        @[@"Dump Symbols", @"Mach-O symtab (C / C++)", @(self.dSy), @3],
        @[@"Dump il2cpp", @"Xuất dump.cs (app Unity)", @(self.dI), @4],
        @[@"Xuất file gốc", @"global-metadata.dat + UnityFramework", @(self.dER), @5],
        @[@"Full offset", @"Cả system framework (file rất nặng)", @(self.dFu), @6],
    ];
    for (NSArray *t in toggles) {
        UISwitch *sw = [UISwitch new];
        sw.on = [t[2] boolValue];
        sw.tag = [t[3] integerValue];
        [sw addTarget:self action:@selector(sC:) forControlEvents:UIControlEventValueChanged];
        UIView *row = [self tR:t[0] subtitle:t[1] sw:sw y:sy width:cw height:rowH];
        [setScroll addSubview:row];
        sy += rowH + 8;
    }
    UILabel *sizeTitle = [[UILabel alloc] initWithFrame:CGRectMake(pad, sy + 4, cw - pad * 2, 20)];
    sizeTitle.text = @"Kích thước panel";
    sizeTitle.font = [UIFont boldSystemFontOfSize:15];
    sizeTitle.textColor = UIColor.whiteColor;
    [setScroll addSubview:sizeTitle];
    UISegmentedControl *sizeSeg = [[UISegmentedControl alloc] initWithItems:@[@"Nhỏ", @"Vừa", @"Lớn"]];
    sizeSeg.frame = CGRectMake(pad, sy + 28, cw - pad * 2, 30);
    sizeSeg.selectedSegmentIndex = (self.sM == 3) ? UISegmentedControlNoSegment : self.sM;
    sizeSeg.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.22];
    [sizeSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateNormal];
    [sizeSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [sizeSeg addTarget:self action:@selector(zC:) forControlEvents:UIControlEventValueChanged];
    [setScroll addSubview:sizeSeg];
    sy += 66;
    UILabel *setNote = [[UILabel alloc] initWithFrame:CGRectMake(pad, sy, cw - pad * 2, 40)];
    setNote.text = @"Cài đặt lưu tự động. Tắt “Tự động Dump” rồi bấm “Dump lại” để dump tay. Kéo góc dưới-phải panel để chỉnh kích thước tùy ý.";
    setNote.font = [UIFont systemFontOfSize:12];
    setNote.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    setNote.numberOfLines = 2;
    [setScroll addSubview:setNote];
    sy += 48;
    setScroll.contentSize = CGSizeMake(cw, sy);
    [self.sTab addSubview:setScroll];
    [self.panel addSubview:self.sTab];

    // ---- Tab About ----
    self.aTab = [[UIView alloc] initWithFrame:CGRectMake(contentX, contentY, cw, contentH)];
    self.aTab.hidden = YES;
    UIScrollView *abScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, cw, contentH)];
    // Can giua noi dung About khi panel cao hon noi dung (khong de khoang trong lech).
    CGFloat ay = (contentH > 466) ? (contentH - 466) / 2 + 8 : 8;
    UIView *bigLogo = [self zL:72];
    bigLogo.center = CGPointMake(cw / 2, ay + 36);
    [abScroll addSubview:bigLogo];
    // Avatar GitHub cua tac gia (tai tu github.com/zheedevVn.png, cache o tmp, loi -> hien logo Z).
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectMake((cw - 72) / 2, ay, 72, 72)];
    avatar.layer.cornerRadius = 36;
    avatar.clipsToBounds = YES;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    [abScroll addSubview:avatar];
    [self loadAvatarInto:avatar];
    ay += 80;
    UILabel *abTitle = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, cw - pad * 2, 26)];
    abTitle.text = [self cfgStr:@"aboutTitle" def:@"Zhee Dump"];
    abTitle.font = [UIFont boldSystemFontOfSize:22];
    abTitle.textColor = UIColor.whiteColor;
    abTitle.textAlignment = NSTextAlignmentCenter;
    [abScroll addSubview:abTitle];
    ay += 28;
    UILabel *abVer = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, cw - pad * 2, 18)];
    abVer.text = [self cfgStr:@"aboutSubtitle" def:@"v4 • Dump offset lúc runtime"];
    abVer.font = [UIFont systemFontOfSize:13];
    abVer.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.65];
    abVer.textAlignment = NSTextAlignmentCenter;
    [abScroll addSubview:abVer];
    ay += 24;
    UILabel *abAuthor = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, cw - pad * 2, 20)];
    abAuthor.text = [self cfgStr:@"aboutAuthor" def:@"Phát triển bởi Hồ Đức Minh — Zhee Dev"];
    abAuthor.font = [UIFont boldSystemFontOfSize:14];
    abAuthor.textColor = UIColor.whiteColor;
    abAuthor.textAlignment = NSTextAlignmentCenter;
    [abScroll addSubview:abAuthor];
    ay += 32;
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(pad, ay, cw - pad * 2, 1)];
    div.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.15];
    [abScroll addSubview:div];
    ay += 12;
    NSDictionary *info = @{
        @"Ứng dụng": NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: NSBundle.mainBundle.bundleIdentifier ?: @"?",
        @"Bundle ID": NSBundle.mainBundle.bundleIdentifier ?: @"?",
        @"Phiên bản": [NSString stringWithFormat:@"%@ (%@)",
                       NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"?",
                       NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"?"],
        @"Thiết bị": [NSString stringWithFormat:@"%@ • iOS %@", UIDevice.currentDevice.model, UIDevice.currentDevice.systemVersion],
        @"Dylib": @"ZheeOffsetDump v4",
        @"GitHub": @"github.com/zheedevVn/XzheeTool",
    };
    for (NSString *k in @[@"Ứng dụng", @"Bundle ID", @"Phiên bản", @"Thiết bị", @"Dylib"]) {
        UIView *row = [self iR:k value:info[k] y:ay width:cw];
        [abScroll addSubview:row];
        ay += 30;
    }
    ay += 4;
    // Nut link mau: Telegram (xanh) + GitHub (xam dam).
    CGFloat abw = (cw - pad * 2 - 8) / 2;
    UIButton *teleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    teleBtn.frame = CGRectMake(pad, ay, abw, 44);
    teleBtn.layer.cornerRadius = 12;
    teleBtn.backgroundColor = [self cfgColor:@"telegramButtonColor" def:[UIColor colorWithRed:0.18 green:0.48 blue:1.0 alpha:1]];
    [teleBtn setTitle:[self cfgStr:@"telegramTitle" def:@"Telegram"] forState:UIControlStateNormal];
    teleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [teleBtn setImage:[UIImage systemImageNamed:@"paperplane"] forState:UIControlStateNormal];
    teleBtn.tintColor = UIColor.whiteColor;
    teleBtn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    teleBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    teleBtn.tag = 101;
    [teleBtn addTarget:self action:@selector(openLink:) forControlEvents:UIControlEventTouchUpInside];
    [abScroll addSubview:teleBtn];
    UIButton *ghBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    ghBtn.frame = CGRectMake(pad + abw + 8, ay, abw, 44);
    ghBtn.layer.cornerRadius = 12;
    ghBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [ghBtn setTitle:[self cfgStr:@"githubTitle" def:@"GitHub"] forState:UIControlStateNormal];
    ghBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [ghBtn setImage:[UIImage systemImageNamed:@"link"] forState:UIControlStateNormal];
    ghBtn.tintColor = UIColor.whiteColor;
    ghBtn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    ghBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    ghBtn.tag = 100;
    [ghBtn addTarget:self action:@selector(openLink:) forControlEvents:UIControlEventTouchUpInside];
    [abScroll addSubview:ghBtn];
    ay += 52;
    ay += 8;
    UILabel *abDesc = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, cw - pad * 2, 60)];
    abDesc.text = @"Dump offset ObjC / Mach-O / il2cpp lúc runtime, chạy trên mọi app. Không hook, không sửa app — chỉ đọc. Dữ liệu xuất ra Documents / Tải về.";
    abDesc.font = [UIFont systemFontOfSize:12];
    abDesc.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.6];
    abDesc.numberOfLines = 3;
    [abScroll addSubview:abDesc];
    ay += 68;
    abScroll.contentSize = CGSizeMake(cw, ay);
    [self.aTab addSubview:abScroll];
    [self.panel addSubview:self.aTab];

    // Tay cam keo goc duoi-phai de resize panel.
    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(w - 30, h - 30, 30, 30)];
    grip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    UIImageView *gripIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]];
    gripIcon.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.7];
    gripIcon.frame = CGRectMake(6, 6, 18, 18);
    [grip addSubview:gripIcon];
    [grip addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(gripPan:)]];
    [self.panel addSubview:grip];
}

- (UIView *)tR:(NSString *)title subtitle:(NSString *)sub sw:(UISwitch *)sw y:(CGFloat)y width:(CGFloat)w height:(CGFloat)h {
    CGFloat pad = 16;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, h)];
    row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    row.layer.cornerRadius = 12;
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(12, (h - 34) / 2, w - pad * 2 - 24 - 60, 20)];
    t.text = title; t.font = [UIFont boldSystemFontOfSize:15]; t.textColor = UIColor.whiteColor;
    [row addSubview:t];
    UILabel *s = [[UILabel alloc] initWithFrame:CGRectMake(12, (h - 34) / 2 + 20, w - pad * 2 - 24 - 60, 16)];
    s.text = sub; s.font = [UIFont systemFontOfSize:12]; s.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    [row addSubview:s];
    sw.frame = CGRectMake(w - pad * 2 - 51 - 12, (h - 31) / 2, 51, 31);
    sw.onTintColor = [UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1];
    [row addSubview:sw];
    [self.allSwitches addObject:sw];
    return row;
}

- (UIView *)iR:(NSString *)key value:(NSString *)value y:(CGFloat)y width:(CGFloat)w {
    CGFloat pad = 16;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, 26)];
    UILabel *k = [[UILabel alloc] initWithFrame:CGRectMake(0, 3, 92, 18)];
    k.text = key; k.font = [UIFont systemFontOfSize:13]; k.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    [row addSubview:k];
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(96, 3, w - pad * 2 - 96, 18)];
    v.text = value; v.font = [UIFont boldSystemFontOfSize:13]; v.textColor = UIColor.whiteColor;
    v.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [row addSubview:v];
    return row;
}

// Hang info bam duoc (GitHub / Telegram) — tag 100 GitHub, 101 Telegram.
- (void)openLink:(UIButton *)b {
    NSString *url = (b.tag == 101) ? @"https://t.me/zheevipv1" : @"https://github.com/zheedevVn/XzheeTool";
    NSURL *u = [NSURL URLWithString:url];
    if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}

// Tai avatar GitHub (github.com/zheedevVn.png) vao UIImageView, cache o tmp.
- (void)loadAvatarInto:(UIImageView *)iv {
    NSString *cache = [NSTemporaryDirectory() stringByAppendingPathComponent:@"zhee-avatar.png"];
    NSData *cached = [NSData dataWithContentsOfFile:cache];
    if (cached) { UIImage *img = [UIImage imageWithData:cached]; if (img) { iv.image = img; return; } }
    NSURL *url = [NSURL URLWithString:[self cfgStr:@"avatarURL" def:@"https://github.com/zheedevVn.png"]];
    if (!url) return;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data || err) return;
        UIImage *img = [UIImage imageWithData:data];
        if (!img) return;
        [data writeToFile:cache atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{ iv.image = img; });
    }] resume];
}

// Keo goc duoi-phai de resize panel (tha ra thi luu kich thuoc tuy chinh + dung lai layout).
- (void)gripPan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [pan translationInView:self.panel];
        CGRect f = self.panel.frame;
        CGRect b = UIScreen.mainScreen.bounds;
        f.size.width = MAX(260, MIN(b.size.width - 16, f.size.width + t.x));
        f.size.height = MAX(320, MIN(b.size.height - 32, f.size.height + t.y));
        self.panel.frame = f;
        [pan setTranslation:CGPointZero inView:self.panel];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        self.customW = self.panel.frame.size.width;
        self.customH = self.panel.frame.size.height;
        self.sM = 3;
        [self sSv];
        [self rP];
    }
}

- (void)updateSideButtons {
    for (UIButton *b in self.sideButtons) {
        BOOL sel = (b.tag == (self.dTab.hidden ? (self.sTab.hidden ? 2 : 1) : 0));
        b.backgroundColor = sel ? [UIColor colorWithRed:0.18 green:0.48 blue:1.0 alpha:1]
                                : [UIColor colorWithWhite:1 alpha:0.06];
    }
}

- (void)sideTap:(UIButton *)b {
    NSInteger i = b.tag;
    self.dTab.hidden = (i != 0);
    self.sTab.hidden = (i != 1);
    self.aTab.hidden = (i != 2);
    [self updateSideButtons];
    UIView *show = (i == 0) ? self.dTab : (i == 1) ? self.sTab : self.aTab;
    show.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ show.alpha = 1; }];
}

- (void)sC:(UISwitch *)sw {
    switch (sw.tag) {
        case 1:
            self.dE = sw.on;
            // Tat Tu dong Dump giua chung -> huy luon dump dang chay.
            if (!sw.on && self.dmp) {
                self.dmpCancel = YES;
                [self lg:@"Đã hủy dump đang chạy (Tự động Dump: TẮT)"];
            }
            break;
        case 2: self.dO = sw.on; break;
        case 3: self.dSy = sw.on; break;
        case 4: self.dI = sw.on; break;
        case 5: self.dER = sw.on; break;
        case 6: self.dFu = sw.on; break;
    }
    [self sSv];
    // Dong bo switch cung chuc nang o tab kia (Dump <-> Cai dat).
    for (UISwitch *other in self.allSwitches) {
        if (other != sw && other.tag == sw.tag) other.on = sw.on;
    }
}

- (void)zC:(UISegmentedControl *)seg {
    self.sM = seg.selectedSegmentIndex;
    [self sSv];
    [self rP];
}

- (void)tP {
    BOOL show = self.panel.hidden;
    self.panel.hidden = NO;
    if (show) [self fetchCfg]; // mo panel -> lay giao dien moi nhat tren GitHub, co doi thi dung lai ngay
    if (show) {
        self.panel.alpha = 0;
        self.panel.transform = CGAffineTransformMakeScale(0.85, 0.85);
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.6 options:0 animations:^{
            self.panel.alpha = 1;
            self.panel.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.22 animations:^{
            self.panel.alpha = 0;
            self.panel.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:^(BOOL f) { self.panel.hidden = YES; }];
    }
}

- (void)dPn:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.fW];
    CGPoint c = self.panel.center;
    c.x += t.x; c.y += t.y;
    CGRect b = self.fW.bounds;
    CGFloat m = 60;
    CGFloat hw = self.panel.bounds.size.width / 2, hh = self.panel.bounds.size.height / 2;
    c.x = MAX(hw - (self.panel.bounds.size.width - m), MIN(b.size.width - hw + (self.panel.bounds.size.width - m), c.x));
    c.y = MAX(hh - (self.panel.bounds.size.height - m), MIN(b.size.height - hh + (self.panel.bounds.size.height - m), c.y));
    self.panel.center = c;
    [pan setTranslation:CGPointZero inView:self.fW];
}

// Chỉ kéo panel khi chạm vào tay cầm mà không trúng nút Đóng.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    CGPoint p = [g locationInView:g.view];
    UIView *hit = [g.view hitTest:p withEvent:nil];
    while (hit) {
        if ([hit isKindOfClass:[UIControl class]]) return NO;
        hit = hit.superview;
    }
    return YES;
}

- (void)dA {
    if (self.dmp) return;
    dispatch_async(dispatch_get_main_queue(), ^{ self.lV.text = @""; });
    [self sD];
}

- (void)eF {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSString *docs = [self dD];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in @[zStr(kS20, sizeof(kS20)), zStr(kS21, sizeof(kS21)), zStr(kS22, sizeof(kS22)), zStr(kS23, sizeof(kS23))]) {
        NSString *p = [docs stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:p]) [urls addObject:[NSURL fileURLWithPath:p]];
    }
    if (urls.count == 0) {
        [self lg:@"Chưa có file để xuất — bấm Dump lại trước"];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *picker = nil;
        if (@available(iOS 16.0, *)) {
            picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:urls];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            picker = [[UIDocumentPickerViewController alloc] initWithURLs:urls inMode:UIDocumentPickerModeExportToService];
#pragma clang diagnostic pop
        }
        UIViewController *host = self.fW.rootViewController;
        if (host) {
            [host presentViewController:picker animated:YES completion:nil];
            [self lg:@"Đã mở trình chọn — chọn thư mục Tải về"];
        } else {
            [self lg:@"Không mở được trình chọn thư mục"];
        }
    });
}

- (void)dF {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [self dD];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:zStr(kS20, sizeof(kS20))] error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:zStr(kS21, sizeof(kS21))] error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:zStr(kS22, sizeof(kS22))] error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:zStr(kS23, sizeof(kS23))] error:nil];
    [self lg:@"Đã xóa file dump (dump.cs, ZheeOffsets.txt, global-metadata.dat, UnityFramework)"];
}

// ---------------------------------------------------------------------------
// Dump
// ---------------------------------------------------------------------------
- (void)sD {
    if (self.dmp) return;
    self.dmp = YES;
    self.dmpCancel = NO;
    self.iDone = NO;
    [self sS:@"Đang chạy…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        @try {
            for (int attempt = 0; attempt < 5; attempt++) {
                if (attempt > 0) [self lg:@"il2cpp chưa sẵn, thử lại lần %d…", attempt + 1];
                [self rD];
                if (self.iDone) break;
                if (self.dmpCancel) break;
                if (attempt < 4) [NSThread sleepForTimeInterval:2.0];
            }
            if (self.dmpCancel) [self sS:@"Đã hủy"];
            else [self sS:@"Xong!"];
        } @catch (NSException *e) {
            [self lg:@"Lỗi: %@", e];
            [self sS:@"Lỗi"];
        }
        self.dmp = NO;
    });
}

- (NSString *)dD {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

- (void)rD {
    @autoreleasepool {
        g_fullOffset = self.dFu;
        [self sP:0];
        long skippedObjC = 0, badIl2cpp = 0;
        uint32_t imgCount = _dyld_image_count();
        NSString *exePath = [NSString stringWithUTF8String:_dyld_get_image_name(0) ?: ""];
        [self lg:@"Bắt đầu dump: %@", NSBundle.mainBundle.bundleIdentifier ?: @"?"];
        [self lg:@"Executable: %@", exePath];
        [self lg:@"Đã load %u image", imgCount];
        zBIC(imgCount);
        zBBF(NSBundle.mainBundle.bundlePath, imgCount);

        // ---- ZheeOffsets.txt: images + ObjC + Mach-O symbols + metadata ----
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"# ZDC v4\n# bundle: %@\n# executable: %@\n# offset = address - base cua image chua no (khong phu thuoc ASLR)\n",
                          NSBundle.mainBundle.bundleIdentifier ?: @"?", exePath];
        [out appendFormat:@"# --- loaded images (framework + binary) ---\n"];
        for (uint32_t i = 0; i < imgCount; i++) {
            uintptr_t b = 0, e = 0;
            zIR(i, &b, &e);
            const char *name = _dyld_get_image_name(i);
            [out appendFormat:@"# [%u] base=0x%lx size=0x%lx %s\n", i,
                              (unsigned long)b, (unsigned long)(e - b), name ? name : "?"];
        }

        // ObjC theo image (mac dinh chi app bundle; Full offset = ca image).
        [out appendFormat:@"\n# --- ObjC per-image (%@) ---\n", g_fullOffset ? @"full: ca image" : @"chi image trong app bundle"];
        NSMutableArray<NSMutableString *> *perImage = [NSMutableArray array];
        for (uint32_t i = 0; i < imgCount; i++) [perImage addObject:[NSMutableString string]];
        long totalObjCClasses = 0, totalObjCMethods = 0;
        int clsCount = self.dO ? objc_getClassList(NULL, 0) : 0;
        if (clsCount > 0) {
            __unsafe_unretained Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * (size_t)clsCount);
            clsCount = objc_getClassList(classes, clsCount);
            qsort(classes, (size_t)clsCount, sizeof(Class), cCN);
            for (int ci = 0; ci < clsCount; ci++) {
                if (self.dmpCancel) break;
                if (ci % 500 == 0) {
                    [self lg:@"ObjC: %d/%d class…", ci, clsCount];
                    [self sP:0.05f + 0.40f * (float)ci / (float)(clsCount > 0 ? clsCount : 1)];
                }
                Class cls = classes[ci];
                const char *clsName = class_getName(cls);
                if (!clsName) continue;
                NSMutableDictionary<NSNumber *, NSMutableString *> *buckets = [NSMutableDictionary dictionary];
                long methodsInClass = 0;
                for (int pass = 0; pass < 2; pass++) {
                    Class target = (pass == 0) ? cls : object_getClass(cls);
                    if (!target) continue;
                    unsigned int mcount = 0;
                    Method *methods = class_copyMethodList(target, &mcount);
                    if (!methods) continue;
                    qsort(methods, mcount, sizeof(Method), cMN);
                    for (unsigned int mi = 0; mi < mcount; mi++) {
                        uintptr_t addr = (uintptr_t)method_getImplementation(methods[mi]);
                        int img = zIC(addr, imgCount);
                        if (img < 0) { skippedObjC++; continue; }
                        if (g_imgInBundle && !g_imgInBundle[img]) continue; // bo method cua system framework
                        uintptr_t b = 0, e = 0;
                        zIR((uint32_t)img, &b, &e);
                        const char *sel = sel_getName(method_getName(methods[mi]));
                        const char *type = method_getTypeEncoding(methods[mi]);
                        NSMutableString *buf = buckets[@(img)];
                        if (!buf) { buf = [NSMutableString string]; buckets[@(img)] = buf; }
                        [buf appendFormat:@"[%s] %c%s | %s | IMP=0x%lx | offset=0x%lx\n",
                                          clsName, (pass == 0 ? '-' : '+'), sel ? sel : "?",
                                          type ? type : "?",
                                          (unsigned long)addr, (unsigned long)(addr - b)];
                        methodsInClass++;
                    }
                    free(methods);
                }
                if (buckets.count == 0) continue;
                totalObjCClasses++;
                totalObjCMethods += methodsInClass;
                for (NSNumber *imgKey in buckets) {
                    [perImage[imgKey.intValue] appendString:buckets[imgKey]];
                }
                unsigned int icount = 0;
                Ivar *ivars = class_copyIvarList(cls, &icount);
                if (ivars && icount > 0) {
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
        if (self.dO) [self lg:@"ObjC xong: %ld classes, %ld methods", totalObjCClasses, totalObjCMethods];
        else [self lg:@"ObjC: TẮT (theo cài đặt)"];
        [self sP:0.45f];
        if (self.dmpCancel) { [self lg:@"Đã hủy dump"]; return; }

        // Mach-O symbols (C/C++) — mac dinh chi app bundle, Full offset = ca image.
        [out appendFormat:@"\n# --- Mach-O symbols (C/C++) - %@ ---\n", g_fullOffset ? @"ca image" : @"image trong app bundle"];
        NSString *bundlePath = NSBundle.mainBundle.bundlePath;
        if (!self.dSy) [self lg:@"Symbols: TẮT (theo cài đặt)"];
        for (uint32_t ii = 0; ii < imgCount && self.dSy; ii++) {
            if (self.dmpCancel) break;
            [self sP:0.45f + 0.15f * (float)ii / (float)(imgCount > 0 ? imgCount : 1)];
            const char *imgNameC = _dyld_get_image_name(ii);
            if (!imgNameC) continue;
            NSString *imgPath = [NSString stringWithUTF8String:imgNameC];
            if (!g_fullOffset && ![imgPath hasPrefix:bundlePath]) continue;
            const struct mach_header_64 *mh2 = (const struct mach_header_64 *)_dyld_get_image_header(ii);
            if (!mh2) continue;
            intptr_t slide2 = _dyld_get_image_vmaddr_slide(ii);
            uint64_t textVmaddr = 0, linkVmaddr = 0, linkFileoff = 0, linkFilesize = 0;
            uint32_t symoff = 0, nsyms = 0, stroff = 0, strsize = 0;
            NSMutableArray<NSString *> *sectNames = [NSMutableArray array];
            const struct load_command *lc2 = (const struct load_command *)((const char *)mh2 + sizeof(struct mach_header_64));
            for (uint32_t k = 0; k < mh2->ncmds; k++) {
                if (lc2->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *seg = (const struct segment_command_64 *)lc2;
                    if (strncmp(seg->segname, "__TEXT", 6) == 0) textVmaddr = seg->vmaddr;
                    if (strncmp(seg->segname, "__LINKEDIT", 10) == 0) {
                        linkVmaddr = seg->vmaddr; linkFileoff = seg->fileoff; linkFilesize = seg->filesize;
                    }
                    const struct section_64 *sec = (const struct section_64 *)((const char *)seg + sizeof(struct segment_command_64));
                    for (uint32_t s = 0; s < seg->nsects; s++) {
                        char buf[33]; memset(buf, 0, sizeof(buf));
                        memcpy(buf, sec[s].segname, 16); memcpy(buf + 17, sec[s].sectname, 16);
                        [sectNames addObject:[NSString stringWithUTF8String:buf]];
                    }
                } else if (lc2->cmd == LC_SYMTAB) {
                    const struct symtab_command *sc = (const struct symtab_command *)lc2;
                    symoff = sc->symoff; nsyms = sc->nsyms; stroff = sc->stroff; strsize = sc->strsize;
                }
                lc2 = (const struct load_command *)((const char *)lc2 + lc2->cmdsize);
            }
            if (nsyms == 0 || linkFilesize == 0) {
                [out appendFormat:@"\n## symtab [%u] %@ (khong co symbol table - co the da strip)\n", ii, imgPath];
                continue;
            }
            if (symoff < linkFileoff || (uint64_t)symoff + (uint64_t)nsyms * sizeof(struct nlist_64) > linkFileoff + linkFilesize ||
                stroff < linkFileoff || (uint64_t)stroff + strsize > linkFileoff + linkFilesize) {
                [out appendFormat:@"\n## symtab [%u] %@ (symtab ngoai vung __LINKEDIT, bo qua)\n", ii, imgPath];
                continue;
            }
            uintptr_t linkBase = (uintptr_t)(linkVmaddr + (uint64_t)slide2);
            const struct nlist_64 *syms = (const struct nlist_64 *)(linkBase + (symoff - linkFileoff));
            const char *strtab = (const char *)(linkBase + (stroff - linkFileoff));
            [out appendFormat:@"\n## symtab [%u] %@ (%u symbols)\n", ii, imgPath, nsyms];
            [self lg:@"Symbol %@: %u symbols", imgPath.lastPathComponent, nsyms];
            long keptSyms = 0;
            for (uint32_t si = 0; si < nsyms; si++) {
                const struct nlist_64 *sym = &syms[si];
                uint8_t t = sym->n_type;
                if (t & N_STAB) continue;
                if ((t & N_TYPE) != N_SECT) continue;
                if (sym->n_un.n_strx >= strsize) continue;
                const char *name = strtab + sym->n_un.n_strx;
                if (!name || !*name) continue;
                NSString *sect = @"?";
                if (sym->n_sect >= 1 && sym->n_sect <= sectNames.count) sect = sectNames[sym->n_sect - 1];
                [out appendFormat:@"  %s | sect=%@ | n_value=0x%llx | offset=0x%llx\n",
                                  name, sect,
                                  (unsigned long long)sym->n_value,
                                  (unsigned long long)(sym->n_value - textVmaddr)];
                keptSyms++;
                if (keptSyms % 20000 == 0) [self lg:@"  symbol %@: %ld…", imgPath.lastPathComponent, keptSyms];
            }
            [out appendFormat:@"# symtab [%u]: %ld symbols dinh nghia\n", ii, keptSyms];
        }

        // Metadata file.
        [self sP:0.60f];
        if (self.dmpCancel) { [self lg:@"Đã hủy dump"]; return; }
        [out appendFormat:@"\n# --- metadata (global-metadata.dat) ---\n"];
        NSString *metaPath = nil;
        NSArray<NSString *> *candidates = @[
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:zStr(kS24, sizeof(kS24))],
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:zStr(kS25, sizeof(kS25))],
        ];
        NSString *frameworksDir = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
        NSArray *fw = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksDir error:nil];
        NSMutableArray *allCandidates = [candidates mutableCopy];
        for (NSString *f in fw ?: @[]) {
            if ([f containsString:@"Unity"]) {
                [allCandidates addObject:[frameworksDir stringByAppendingPathComponent:[f stringByAppendingPathComponent:zStr(kS24, sizeof(kS24))]]];
            }
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:NSBundle.mainBundle.bundlePath];
        int depthGuard = 0;
        for (NSString *p in en) {
            if (++depthGuard > 20000) break;
            if ([p.lastPathComponent isEqualToString:zStr(kS22, sizeof(kS22))]) {
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
                [out appendFormat:@"# sanity: 0x%x (mong doi 0xfab11baf)\n# metadata version: %u\n", u32[0], u32[1]];
                [out appendFormat:@"# stringLiteralCount: %u, stringCount: %u\n", u32[3], u32[7]];
            }
            [self lg:@"Metadata: %@ (%llu bytes)", metaPath.lastPathComponent, fsize];
        } else {
            [out appendFormat:@"# khong tim thay global-metadata.dat\n"];
            [self lg:@"Không tìm thấy global-metadata.dat"];
        }

        // Export file goc cho Il2CppDumper tren PC: global-metadata.dat + binary UnityFramework.
        if (!self.dER) [self lg:@"Xuất file gốc: TẮT (theo cài đặt)"];
        if (self.dER && metaPath) {
            NSString *metaDest = [[self dD] stringByAppendingPathComponent:zStr(kS22, sizeof(kS22))];
            [fm removeItemAtPath:metaDest error:nil];
            NSError *copyErr = nil;
            if ([fm copyItemAtPath:metaPath toPath:metaDest error:&copyErr]) {
                [self lg:@"Đã xuất global-metadata.dat -> Documents"];
            } else {
                [self lg:@"Copy global-metadata.dat lỗi: %@", copyErr];
            }
        }
        NSString *ufPath = nil;
        NSString *ufDirect = [frameworksDir stringByAppendingPathComponent:zStr(kS26, sizeof(kS26))];
        if ([fm fileExistsAtPath:ufDirect]) {
            ufPath = ufDirect;
        } else {
            NSDirectoryEnumerator *ufe = [fm enumeratorAtPath:frameworksDir];
            int ufGuard = 0;
            for (NSString *p in ufe) {
                if (++ufGuard > 5000) break;
                if ([p.lastPathComponent isEqualToString:zStr(kS23, sizeof(kS23))]) {
                    ufPath = [frameworksDir stringByAppendingPathComponent:p];
                    break;
                }
            }
        }
        if (self.dER && ufPath) {
            NSString *ufDest = [[self dD] stringByAppendingPathComponent:zStr(kS23, sizeof(kS23))];
            [fm removeItemAtPath:ufDest error:nil];
            NSError *ufErr = nil;
            if ([fm copyItemAtPath:ufPath toPath:ufDest error:&ufErr]) {
                unsigned long long usz = [[fm attributesOfItemAtPath:ufDest error:nil][NSFileSize] unsignedLongLongValue];
                [self lg:@"Đã xuất UnityFramework (%llu bytes) -> Documents", usz];
            } else {
                [self lg:@"Copy UnityFramework lỗi: %@", ufErr];
            }
        } else {
            [self lg:@"Không tìm thấy UnityFramework binary"];
        }

        [self sP:0.65f];
        if (self.dmpCancel) { [self lg:@"Đã hủy dump"]; return; }
        NSString *offsetsPath = [[self dD] stringByAppendingPathComponent:zStr(kS21, sizeof(kS21))];
        NSError *err = nil;
        [out writeToFile:offsetsPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) [self lg:@"Ghi ZheeOffsets.txt lỗi: %@", err];
        else [self lg:@"Đã xuất ZheeOffsets.txt"];

        // ---- dump.cs (il2cpp, kiểu Il2CppDumper) ----
        NSMutableString *cs = [NSMutableString string];
        [cs appendFormat:@"// Dumped by ZDC\n// Bundle: %@\n// Date: %@\n// RVA = offset (VA - imageBase)\n\n",
                         NSBundle.mainBundle.bundleIdentifier ?: @"?", [NSDate date]];
        FnDomainGet domainGet = (FnDomainGet)zSym(zChr(kS00, sizeof(kS00)));
        if (!self.dI) {
            [cs appendFormat:@"// il2cpp: tat theo cai dat\n"];
            [self lg:@"il2cpp: TẮT (theo cài đặt)"];
            self.iDone = YES;
        } else if (!domainGet) {
            [cs appendFormat:@"// Khong phai app Unity (khong co domain API)\n"];
            [self lg:@"Không phải app Unity — dump.cs chỉ có header"];
            self.iDone = YES;
        } else {
            Il2CppDomain *domain = domainGet();
            if (!domain) {
                [cs appendFormat:@"// il2cpp chua khoi tao\n"];
                [self lg:@"il2cpp chưa khởi tạo"];
            } else {
                FnDomainAssemblies assembliesFn = (FnDomainAssemblies)zSym(zChr(kS01, sizeof(kS01)));
                FnAssemblyImage assemblyImage = (FnAssemblyImage)zSym(zChr(kS02, sizeof(kS02)));
                FnImageName imageName = (FnImageName)zSym(zChr(kS03, sizeof(kS03)));
                FnImageClassCount classCountFn = (FnImageClassCount)zSym(zChr(kS04, sizeof(kS04)));
                FnImageGetClass getClass = (FnImageGetClass)zSym(zChr(kS05, sizeof(kS05)));
                FnClassMethods classMethods = (FnClassMethods)zSym(zChr(kS06, sizeof(kS06)));
                FnClassFields classFields = (FnClassFields)zSym(zChr(kS07, sizeof(kS07)));
                FnClassName className = (FnClassName)zSym(zChr(kS08, sizeof(kS08)));
                FnClassNamespace classNs = (FnClassNamespace)zSym(zChr(kS09, sizeof(kS09)));
                FnMethodName methodName = (FnMethodName)zSym(zChr(kS10, sizeof(kS10)));
                FnMethodRet methodRet = (FnMethodRet)zSym(zChr(kS11, sizeof(kS11)));
                FnMethodParamCount paramCount = (FnMethodParamCount)zSym(zChr(kS12, sizeof(kS12)));
                FnMethodParam paramAt = (FnMethodParam)zSym(zChr(kS13, sizeof(kS13)));
                FnMethodParamName paramName = (FnMethodParamName)zSym(zChr(kS14, sizeof(kS14)));
                FnFieldName fieldName = (FnFieldName)zSym(zChr(kS15, sizeof(kS15)));
                FnFieldOffset fieldOffset = (FnFieldOffset)zSym(zChr(kS16, sizeof(kS16)));
                FnFieldType fieldType = (FnFieldType)zSym(zChr(kS17, sizeof(kS17)));
                FnTypeName typeName = (FnTypeName)zSym(zChr(kS18, sizeof(kS18)));
                FnFree il2cppFree = (FnFree)zSym(zChr(kS19, sizeof(kS19)));
                if (!assembliesFn || !assemblyImage || !getClass || !classMethods || !className) {
                    [cs appendFormat:@"// Thieu il2cpp API (khong dump duoc)\n"];
                    [self lg:@"Thiếu il2cpp API"];
                    self.iDone = YES;
                } else {
                    size_t asmCount = 0;
                    const Il2CppAssembly **asms = assembliesFn(domain, &asmCount);
                    long totalClasses = 0, totalMethods = 0, totalFields = 0;
                    for (size_t ai = 0; ai < asmCount; ai++) {
                        if (self.dmpCancel) break;
                        const Il2CppImage *img = assemblyImage(asms[ai]);
                        if (!img) continue;
                        const char *asmName = imageName ? (imageName(img) ?: "?") : "?";
                        [cs appendFormat:@"// Image: %s\n", asmName];
                        [self lg:@"Dump il2cpp: %s", [NSString stringWithUTF8String:asmName]];
                        [self sP:0.65f + 0.35f * (float)ai / (float)(asmCount > 0 ? asmCount : 1)];
                        size_t cc = classCountFn ? classCountFn(img) : 0;
                        // Nhóm class theo namespace.
                        NSMutableDictionary<NSString *, NSMutableString *> *nsBuckets = [NSMutableDictionary dictionary];
                        NSMutableArray<NSString *> *nsOrder = [NSMutableArray array];
                        for (size_t ci = 0; ci < cc; ci++) {
                            const Il2CppClass *klass = getClass(img, ci);
                            if (!klass) continue;
                            const char *kName = className(klass) ?: "?";
                            const char *kNs = classNs ? (classNs(klass) ?: "") : "";
                            NSString *nsKey = [NSString stringWithUTF8String:kNs];
                            NSMutableString *bucket = nsBuckets[nsKey];
                            if (!bucket) { bucket = [NSMutableString string]; nsBuckets[nsKey] = bucket; [nsOrder addObject:nsKey]; }
                            [bucket appendFormat:@"\t// Class: %s.%s\n\tpublic class %s\n\t{\n", kNs, kName, kName];
                            // Fields
                            if (classFields) {
                                [bucket appendFormat:@"\t\t// Fields\n"];
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
                                    [bucket appendFormat:@"\t\tpublic %@ %@; // 0x%lx\n", ft, [NSString stringWithUTF8String:fName], (unsigned long)fo];
                                    totalFields++;
                                }
                                [bucket appendFormat:@"\n"];
                            }
                            // Methods
                            if (classMethods) {
                                [bucket appendFormat:@"\t\t// Methods\n"];
                                void *iter = NULL;
                                const MethodInfo *m = NULL;
                                while ((m = classMethods(klass, &iter)) != NULL) {
                                    void *mp = *(void **)m;
                                    const char *mName = methodName ? (methodName(m) ?: "?") : "?";
                                    NSMutableString *sig = [NSMutableString string];
                                    if (methodRet && typeName) {
                                        char *rt = typeName(methodRet(m));
                                        [sig appendFormat:@"%s", rt ?: "?"];
                                        if (rt && il2cppFree) il2cppFree(rt);
                                    } else [sig appendString:@"?"];
                                    [sig appendFormat:@" %s(", mName];
                                    if (paramCount && paramAt && typeName) {
                                        uint8_t pc = paramCount(m);
                                        for (uint8_t pi = 0; pi < pc; pi++) {
                                            char *pt = typeName(paramAt(m, pi));
                                            const char *pn = paramName ? (paramName(m, pi) ?: "") : "";
                                            [sig appendFormat:@"%s%s %s", pi ? ", " : "", pt ?: "?", pn];
                                            if (pt && il2cppFree) il2cppFree(pt);
                                        }
                                    }
                                    [sig appendString:@")"];
                                    int imgIdx = zIC((uintptr_t)mp, imgCount);
                                    if (imgIdx < 0) badIl2cpp++;
                                    uintptr_t b = 0, e = 0;
                                    if (imgIdx >= 0) zIR((uint32_t)imgIdx, &b, &e);
                                    unsigned long rva = imgIdx >= 0 ? (unsigned long)((uintptr_t)mp - b) : 0;
                                    [bucket appendFormat:@"\t\tpublic %@; // 0x%lx\n", sig, rva];
                                    totalMethods++;
                                }
                            }
                            [bucket appendFormat:@"\t}\n\n"];
                            totalClasses++;
                            if (totalClasses % 500 == 0) [self lg:@"  il2cpp: %ld classes…", totalClasses];
                        }
                        // Xuất namespace đã sắp xếp.
                        NSArray *sortedNs = [nsOrder sortedArrayUsingSelector:@selector(compare:)];
                        for (NSString *ns in sortedNs) {
                            [cs appendFormat:@"namespace %@\n{\n%@}\n\n", ns, nsBuckets[ns]];
                        }
                    }
                    [cs appendFormat:@"// Tong: %ld classes, %ld methods, %ld fields\n", totalClasses, totalMethods, totalFields];
                    [self lg:@"il2cpp xong: %ld classes, %ld methods, %ld fields", totalClasses, totalMethods, totalFields];
                    self.iDone = YES;
                }
            }
        }
        NSString *csPath = [[self dD] stringByAppendingPathComponent:zStr(kS20, sizeof(kS20))];
        if (self.dmpCancel) { [self lg:@"Đã hủy dump"]; return; }
        [cs writeToFile:csPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) [self lg:@"Ghi dump.cs lỗi: %@", err];
        else [self lg:@"Đã xuất dump.cs -> %@", csPath];
        [self sP:1.0f];
        if (skippedObjC == 0 && badIl2cpp == 0) [self lg:@"Kiểm tra: tất cả offset nằm trong image — chính xác"];
        else [self lg:@"Kiểm tra: ObjC bỏ qua %ld method, il2cpp %ld method ngoài image", skippedObjC, badIl2cpp];
        NSMutableArray *doneFiles = [NSMutableArray array];
        [doneFiles addObject:zStr(kS21, sizeof(kS21))];
        if (self.dI) [doneFiles addObject:zStr(kS20, sizeof(kS20))];
        if (self.dER) { [doneFiles addObject:zStr(kS22, sizeof(kS22))]; [doneFiles addObject:zStr(kS23, sizeof(kS23))]; }
        [self lg:@"HOÀN TẤT. Documents: %@", [doneFiles componentsJoinedByString:@", "]];
    }
}

@end

__attribute__((constructor)) static void ZDCInit(void) {
    // Delay ngan 1–2s (lech timing, tranh fingerprint), roi hien panel + chay dump.
    double delay = 1.0 + (double)arc4random_uniform(1000) / 1000.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try { [[ZDC sh] st]; } @catch (NSException *e) {}
    });
}
