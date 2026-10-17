// ZheeOffsetDump.m v4 — Dylib dump offset: panel 3 tab + log live + xuất dump.cs.
//
// Inject vào app bất kỳ (LC_LOAD_DYLIB). Mở app -> hiện panel -> tự chạy
// dump, log chạy live trong panel -> xong tự xuất file ra Documents:
//   - dump.cs          (il2cpp, kiểu Il2CppDumper: namespace -> class ->
//                       field offset + method RVA)
//   - ZheeOffsets.txt  (image/framework, ObjC theo image, Mach-O symbols,
//                       metadata global-metadata.dat)
//   - global-metadata.dat + UnityFramework (file gốc cho Il2CppDumper)
//
// Panel 3 tab: Dump (log + tiến trình) | Cài đặt (toggle từng phần,
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

static void *ZheeSym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

// ---------------------------------------------------------------------------
// Image range
// ---------------------------------------------------------------------------
// Cache range cua image: tinh 1 lan moi lan dump, tim bang binary search.
// (Ban cu goi ZheeImageRange cho MOI method -> quet lai 1342 image + parse
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

static void ZheeBuildBundleFlags(NSString *bundlePath, uint32_t count) {
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

static BOOL ZheeImageRangeUncached(uint32_t idx, uintptr_t *outBase, uintptr_t *outEnd) {
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

static void ZheeBuildImageCache(uint32_t count) {
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
        ZheeImageRangeUncached(i, &b, &e);
        g_imgBase[i] = b; g_imgEnd[i] = e; g_imgSorted[i] = i;
    }
    qsort(g_imgSorted, count, sizeof(uint32_t), cmpImageBase);
    g_imgCacheCount = count;
}

static BOOL ZheeImageRange(uint32_t idx, uintptr_t *outBase, uintptr_t *outEnd) {
    if (idx < g_imgCacheCount && g_imgBase) {
        *outBase = g_imgBase[idx];
        *outEnd = g_imgEnd[idx];
        return YES;
    }
    return ZheeImageRangeUncached(idx, outBase, outEnd);
}

static int ZheeImageContaining(uintptr_t p, uint32_t count) {
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
        if (ZheeImageRangeUncached(i, &b, &e) && p >= b && p < e) return (int)i;
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
// Panel + log
// ---------------------------------------------------------------------------
@interface ZheePassthroughWindow : UIWindow
@end
@implementation ZheePassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface ZheeOffsetDump : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIWindow *floatWindow;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *dumpButton;
@property (nonatomic, strong) UISegmentedControl *tabControl;
@property (nonatomic, strong) UIView *dumpTab;
@property (nonatomic, strong) UIView *settingsTab;
@property (nonatomic, strong) UIView *aboutTab;
@property (nonatomic, strong) UIProgressView *progressBar;
@property (nonatomic, assign) BOOL dumping;
@property (nonatomic, assign) BOOL il2cppDone;
// Cai dat (luu UserDefaults, prefix zheedump.)
@property (nonatomic, assign) BOOL dumpEnabled;   // tu dong dump khi mo app
@property (nonatomic, assign) BOOL dumpObjC;
@property (nonatomic, assign) BOOL dumpSymtab;
@property (nonatomic, assign) BOOL dumpIl2cpp;
@property (nonatomic, assign) BOOL dumpExportRaw;
@property (nonatomic, assign) BOOL dumpFull;      // full offset: ca system framework
@property (nonatomic, assign) NSInteger sizeMode; // 0 Nho, 1 Vua, 2 Lon
@end

@implementation ZheeOffsetDump

+ (instancetype)shared { static ZheeOffsetDump *s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [ZheeOffsetDump new]; }); return s; }

- (UIColor *)brandBlue { return [UIColor colorWithRed:0.11 green:0.63 blue:0.95 alpha:1]; }
- (UIColor *)brandCyan { return [UIColor colorWithRed:0.00 green:0.82 blue:1.00 alpha:1]; }

// Log live: ghi vào panel + NSLog.
- (void)log:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ZheeOffsetDump] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.logView) return;
        NSString *line = [NSString stringWithFormat:@"%@\n", msg];
        self.logView.text = [self.logView.text stringByAppendingString:line];
        NSRange end = NSMakeRange(self.logView.text.length, 0);
        [self.logView scrollRangeToVisible:end];
    });
}

- (void)setStatus:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = s; });
}

- (void)setProgress:(float)p {
    dispatch_async(dispatch_get_main_queue(), ^{ self.progressBar.progress = p; });
}

// ---------------------------------------------------------------------------
// Cai dat (UserDefaults) + logo ZheeSign + helpers UI
// ---------------------------------------------------------------------------
- (void)loadSettings {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    self.dumpEnabled = [d objectForKey:@"zheedump.auto"] ? [d boolForKey:@"zheedump.auto"] : YES;
    self.dumpObjC = [d objectForKey:@"zheedump.objc"] ? [d boolForKey:@"zheedump.objc"] : YES;
    self.dumpSymtab = [d objectForKey:@"zheedump.sym"] ? [d boolForKey:@"zheedump.sym"] : YES;
    self.dumpIl2cpp = [d objectForKey:@"zheedump.il2cpp"] ? [d boolForKey:@"zheedump.il2cpp"] : YES;
    self.dumpExportRaw = [d objectForKey:@"zheedump.exportraw"] ? [d boolForKey:@"zheedump.exportraw"] : YES;
    self.dumpFull = [d boolForKey:@"zheedump.full"]; // mac dinh NO: chi app bundle
    self.sizeMode = [d integerForKey:@"zheedump.size"]; // 0 Nho, 1 Vua, 2 Lon
    if (self.sizeMode < 0 || self.sizeMode > 2) self.sizeMode = 1;
}

- (void)saveSettings {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:self.dumpEnabled forKey:@"zheedump.auto"];
    [d setBool:self.dumpObjC forKey:@"zheedump.objc"];
    [d setBool:self.dumpSymtab forKey:@"zheedump.sym"];
    [d setBool:self.dumpIl2cpp forKey:@"zheedump.il2cpp"];
    [d setBool:self.dumpExportRaw forKey:@"zheedump.exportraw"];
    [d setBool:self.dumpFull forKey:@"zheedump.full"];
    [d setInteger:self.sizeMode forKey:@"zheedump.size"];
}

// Logo ZheeSign: chu Z neon (cyan -> tim -> hong) tren nen toi.
- (UIView *)zheeLogoViewWithSize:(CGFloat)s {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s, s)];
    CATextLayer *text = [CATextLayer layer];
    text.string = @"Z";
    text.font = @"ArialRoundedMTBold";
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

- (CGSize)panelSizeForMode:(NSInteger)mode screen:(CGRect)screen {
    if (mode == 0) return CGSizeMake(MIN(screen.size.width - 32, 300), MIN(screen.size.height - 160, 420));
    if (mode == 2) return CGSizeMake(MIN(screen.size.width - 24, 430), MIN(screen.size.height - 80, 640));
    return CGSizeMake(MIN(screen.size.width - 32, 360), MIN(screen.size.height - 120, 520));
}

- (void)setup {
    @try {
        [self loadSettings];
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
        }
        if (!scene) { for (UIScene *s in UIApplication.sharedApplication.connectedScenes) { if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; } } }

        CGRect screen = UIScreen.mainScreen.bounds;
        CGFloat size = 56;
        self.floatWindow = scene ? [[ZheePassthroughWindow alloc] initWithWindowScene:scene] : [[ZheePassthroughWindow alloc] initWithFrame:screen];
        self.floatWindow.frame = screen;
        self.floatWindow.windowLevel = UIWindowLevelAlert + 1;
        self.floatWindow.backgroundColor = UIColor.clearColor;
        // Host VC trong suot de present UIDocumentPicker (view tat tuong tac -> cham xuyen).
        UIViewController *host = [UIViewController new];
        host.view.userInteractionEnabled = NO;
        self.floatWindow.rootViewController = host;

        self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatButton.frame = CGRectMake(screen.size.width - size - 16, screen.size.height / 2 - size / 2, size, size);
        self.floatButton.layer.cornerRadius = size / 2;
        self.floatButton.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.09 alpha:1];
        self.floatButton.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.25].CGColor;
        self.floatButton.layer.borderWidth = 1;
        self.floatButton.layer.shadowColor = UIColor.blackColor.CGColor;
        self.floatButton.layer.shadowOpacity = 0.45; self.floatButton.layer.shadowRadius = 10;
        self.floatButton.layer.shadowOffset = CGSizeMake(0, 4);
        UIView *logo = [self zheeLogoViewWithSize:size * 0.62];
        logo.center = CGPointMake(size / 2, size / 2);
        logo.userInteractionEnabled = NO;
        [self.floatButton addSubview:logo];
        [self.floatButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        [self.floatButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFloat:)]];
        [self.floatWindow addSubview:self.floatButton];

        [self buildPanel];
        self.floatWindow.hidden = NO;
        // Xoay ngang/doc: dung lai panel + keo nut noi vao trong man hinh.
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOrientationChange)
                                                     name:UIDeviceOrientationDidChangeNotification object:nil];
        // Mo panel ngay + chay dump neu bat tu dong.
        if (self.dumpEnabled) [self startDump];
        else [self log:@"Tự động dump: TẮT (bật trong tab Cài đặt)"];
    } @catch (NSException *e) {}
}

- (void)handleOrientationChange {
    UIDeviceOrientation o = UIDevice.currentDevice.orientation;
    if (o != UIDeviceOrientationPortrait && o != UIDeviceOrientationLandscapeLeft &&
        o != UIDeviceOrientationLandscapeRight && o != UIDeviceOrientationPortraitUpsideDown) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat r = 28;
        CGPoint c = self.floatButton.center;
        c.x = MAX(r, MIN(b.size.width - r, c.x));
        c.y = MAX(r + 40, MIN(b.size.height - r - 40, c.y));
        self.floatButton.center = c;
        [self rebuildPanel];
    });
}

// Dung lai panel (giữ log + tab) — dung khi doi kich thuoc / xoay man hinh.
- (void)rebuildPanel {
    NSString *savedLog = self.logView.text ?: @"";
    NSInteger savedTab = self.tabControl ? self.tabControl.selectedSegmentIndex : 0;
    [self.panel removeFromSuperview];
    self.panel = nil;
    [self buildPanel];
    self.logView.text = savedLog;
    NSRange end = NSMakeRange(self.logView.text.length, 0);
    [self.logView scrollRangeToVisible:end];
    self.tabControl.selectedSegmentIndex = savedTab;
    [self tabChanged];
}

- (void)dragFloat:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.floatWindow];
    CGPoint c = self.floatButton.center;
    c.x += t.x; c.y += t.y;
    CGRect b = self.floatWindow.bounds;
    CGFloat r = 28;
    c.x = MAX(r, MIN(b.size.width - r, c.x));
    c.y = MAX(r + 40, MIN(b.size.height - r - 40, c.y));
    self.floatButton.center = c;
    [pan setTranslation:CGPointZero inView:self.floatWindow];
}

- (void)buildPanel {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGSize sz = [self panelSizeForMode:self.sizeMode screen:screen];
    CGFloat w = sz.width, h = sz.height;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2, (screen.size.height - h) / 2, w, h)];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.4; self.panel.layer.shadowRadius = 20;
    self.panel.layer.shadowOffset = CGSizeMake(0, 10);
    self.panel.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.18].CGColor;
    self.panel.layer.borderWidth = 1;
    self.panel.clipsToBounds = YES;
    [self.floatWindow addSubview:self.panel];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = self.panel.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:blur];

    // Thanh tiêu đề = tay cầm kéo panel.
    CGFloat pad = 16;
    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 48)];
    [self.panel addSubview:handle];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    panelPan.delegate = self;
    [handle addGestureRecognizer:panelPan];

    UIView *miniLogo = [self zheeLogoViewWithSize:26];
    miniLogo.frame = CGRectMake(pad, 11, 26, 26);
    miniLogo.userInteractionEnabled = NO;
    [handle addSubview:miniLogo];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad + 32, 12, w - pad * 2 - 36 - 32, 24)];
    title.text = @"Zhee Dump"; title.font = [UIFont boldSystemFontOfSize:19]; title.textColor = UIColor.whiteColor;
    [handle addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w - 40, 10, 28, 28);
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.7];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [handle addSubview:close];

    // Tab: Dump | Cài đặt | About.
    self.tabControl = [[UISegmentedControl alloc] initWithItems:@[@"Dump", @"Cài đặt", @"About"]];
    self.tabControl.frame = CGRectMake(pad, 52, w - pad * 2, 30);
    self.tabControl.selectedSegmentIndex = 0;
    self.tabControl.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.22];
    [self.tabControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateNormal];
    [self.tabControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [self.tabControl addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.tabControl];

    CGFloat contentY = 90;
    CGFloat contentH = h - contentY - 12;

    // ---- Tab Dump ----
    self.dumpTab = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, w, contentH)];
    CGFloat exportY = contentH - 38;
    CGFloat row1Y = exportY - 8 - 38;
    CGFloat statusY = row1Y - 8 - 20;
    CGFloat progY = statusY - 6 - 4;
    CGFloat logH = progY - 8;
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(pad, 0, w - pad * 2, logH)];
    self.logView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.35];
    self.logView.layer.cornerRadius = 12;
    self.logView.textColor = [UIColor colorWithRed:0.7 green:1.0 blue:0.7 alpha:1];
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.text = @"";
    [self.dumpTab addSubview:self.logView];

    self.progressBar = [[UIProgressView alloc] initWithFrame:CGRectMake(pad, progY, w - pad * 2, 4)];
    self.progressBar.progressTintColor = self.brandCyan;
    self.progressBar.trackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
    self.progressBar.progress = 0;
    [self.dumpTab addSubview:self.progressBar];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, statusY, w - pad * 2, 20)];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.8];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"Đang chạy…";
    [self.dumpTab addSubview:self.statusLabel];

    self.dumpButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat bw = (w - pad * 2 - 8) / 2;
    self.dumpButton.frame = CGRectMake(pad, row1Y, bw, 38);
    self.dumpButton.layer.cornerRadius = 19;
    CAGradientLayer *bg = [CAGradientLayer layer];
    bg.frame = self.dumpButton.bounds;
    bg.colors = @[(__bridge id)self.brandBlue.CGColor, (__bridge id)self.brandCyan.CGColor];
    bg.startPoint = CGPointMake(0, 0.5); bg.endPoint = CGPointMake(1, 0.5);
    bg.cornerRadius = 19;
    [self.dumpButton.layer insertSublayer:bg atIndex:0];
    [self.dumpButton setTitle:@"Dump lại" forState:UIControlStateNormal];
    self.dumpButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.dumpButton addTarget:self action:@selector(dumpAgain) forControlEvents:UIControlEventTouchUpInside];
    [self.dumpTab addSubview:self.dumpButton];

    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    deleteButton.frame = CGRectMake(pad + bw + 8, row1Y, bw, 38);
    deleteButton.layer.cornerRadius = 19;
    deleteButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    [deleteButton setTitle:@"Xóa file" forState:UIControlStateNormal];
    deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [deleteButton addTarget:self action:@selector(deleteFiles) forControlEvents:UIControlEventTouchUpInside];
    [self.dumpTab addSubview:deleteButton];

    UIButton *exportButton = [UIButton buttonWithType:UIButtonTypeCustom];
    exportButton.frame = CGRectMake(pad, exportY, w - pad * 2, 38);
    exportButton.layer.cornerRadius = 19;
    exportButton.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.45].CGColor;
    exportButton.layer.borderWidth = 1;
    exportButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [exportButton setTitle:@"Xuất ra Tải về" forState:UIControlStateNormal];
    exportButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [exportButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [exportButton addTarget:self action:@selector(exportFiles) forControlEvents:UIControlEventTouchUpInside];
    [self.dumpTab addSubview:exportButton];
    [self.panel addSubview:self.dumpTab];

    // ---- Tab Cài đặt ----
    self.settingsTab = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, w, contentH)];
    self.settingsTab.hidden = YES;
    UIScrollView *setScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, contentH)];
    CGFloat sy = 0;
    NSArray *toggles = @[
        @[@"Tự động Dump", @"Chạy dump ngay khi mở app", @(self.dumpEnabled), @1],
        @[@"Dump ObjC", @"Class / method ObjC theo image", @(self.dumpObjC), @2],
        @[@"Dump Symbols", @"Mach-O symtab (C / C++)", @(self.dumpSymtab), @3],
        @[@"Dump il2cpp", @"Xuất dump.cs (app Unity)", @(self.dumpIl2cpp), @4],
        @[@"Xuất file gốc", @"global-metadata.dat + UnityFramework", @(self.dumpExportRaw), @5],
        @[@"Full offset", @"Cả system framework (file rất nặng)", @(self.dumpFull), @6],
    ];
    for (NSArray *t in toggles) {
        UISwitch *sw = [UISwitch new];
        sw.on = [t[2] boolValue];
        sw.tag = [t[3] integerValue];
        [sw addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];
        UIView *row = [self toggleRowWithTitle:t[0] subtitle:t[1] sw:sw y:sy width:w];
        [setScroll addSubview:row];
        sy += 62;
    }
    UILabel *sizeTitle = [[UILabel alloc] initWithFrame:CGRectMake(pad, sy + 4, w - pad * 2, 20)];
    sizeTitle.text = @"Kích thước panel";
    sizeTitle.font = [UIFont boldSystemFontOfSize:15];
    sizeTitle.textColor = UIColor.whiteColor;
    [setScroll addSubview:sizeTitle];
    UISegmentedControl *sizeSeg = [[UISegmentedControl alloc] initWithItems:@[@"Nhỏ", @"Vừa", @"Lớn"]];
    sizeSeg.frame = CGRectMake(pad, sy + 28, w - pad * 2, 30);
    sizeSeg.selectedSegmentIndex = self.sizeMode;
    sizeSeg.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.22];
    [sizeSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateNormal];
    [sizeSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [sizeSeg addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
    [setScroll addSubview:sizeSeg];
    sy += 66;
    UILabel *setNote = [[UILabel alloc] initWithFrame:CGRectMake(pad, sy, w - pad * 2, 40)];
    setNote.text = @"Cài đặt lưu tự động. Tắt “Tự động Dump” rồi bấm “Dump lại” để dump tay.";
    setNote.font = [UIFont systemFontOfSize:12];
    setNote.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    setNote.numberOfLines = 2;
    [setScroll addSubview:setNote];
    sy += 48;
    setScroll.contentSize = CGSizeMake(w, sy);
    [self.settingsTab addSubview:setScroll];
    [self.panel addSubview:self.settingsTab];

    // ---- Tab About ----
    self.aboutTab = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, w, contentH)];
    self.aboutTab.hidden = YES;
    UIScrollView *abScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, contentH)];
    CGFloat ay = 8;
    UIView *bigLogo = [self zheeLogoViewWithSize:72];
    bigLogo.center = CGPointMake(w / 2, ay + 36);
    [abScroll addSubview:bigLogo];
    ay += 80;
    UILabel *abTitle = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, w - pad * 2, 26)];
    abTitle.text = @"Zhee Dump";
    abTitle.font = [UIFont boldSystemFontOfSize:22];
    abTitle.textColor = UIColor.whiteColor;
    abTitle.textAlignment = NSTextAlignmentCenter;
    [abScroll addSubview:abTitle];
    ay += 28;
    UILabel *abVer = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, w - pad * 2, 18)];
    abVer.text = @"v4 • Dump offset lúc runtime";
    abVer.font = [UIFont systemFontOfSize:13];
    abVer.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.65];
    abVer.textAlignment = NSTextAlignmentCenter;
    [abScroll addSubview:abVer];
    ay += 24;
    UILabel *abAuthor = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, w - pad * 2, 20)];
    abAuthor.text = @"Phát triển bởi Hồ Đức Minh — Zhee Dev";
    abAuthor.font = [UIFont boldSystemFontOfSize:14];
    abAuthor.textColor = UIColor.whiteColor;
    abAuthor.textAlignment = NSTextAlignmentCenter;
    [abScroll addSubview:abAuthor];
    ay += 32;
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(pad, ay, w - pad * 2, 1)];
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
    for (NSString *k in @[@"Ứng dụng", @"Bundle ID", @"Phiên bản", @"Thiết bị", @"Dylib", @"GitHub"]) {
        UIView *row = [self infoRowWithKey:k value:info[k] y:ay width:w];
        [abScroll addSubview:row];
        ay += 30;
    }
    ay += 8;
    UILabel *abDesc = [[UILabel alloc] initWithFrame:CGRectMake(pad, ay, w - pad * 2, 60)];
    abDesc.text = @"Dump offset ObjC / Mach-O / il2cpp lúc runtime, chạy trên mọi app. Không hook, không sửa app — chỉ đọc. Dữ liệu xuất ra Documents / Tải về.";
    abDesc.font = [UIFont systemFontOfSize:12];
    abDesc.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.6];
    abDesc.numberOfLines = 3;
    [abScroll addSubview:abDesc];
    ay += 68;
    abScroll.contentSize = CGSizeMake(w, ay);
    [self.aboutTab addSubview:abScroll];
    [self.panel addSubview:self.aboutTab];
}

- (UIView *)toggleRowWithTitle:(NSString *)title subtitle:(NSString *)sub sw:(UISwitch *)sw y:(CGFloat)y width:(CGFloat)w {
    CGFloat pad = 16;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, 54)];
    row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    row.layer.cornerRadius = 12;
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, w - pad * 2 - 24 - 60, 20)];
    t.text = title; t.font = [UIFont boldSystemFontOfSize:15]; t.textColor = UIColor.whiteColor;
    [row addSubview:t];
    UILabel *s = [[UILabel alloc] initWithFrame:CGRectMake(12, 29, w - pad * 2 - 24 - 60, 16)];
    s.text = sub; s.font = [UIFont systemFontOfSize:12]; s.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    [row addSubview:s];
    sw.frame = CGRectMake(w - pad * 2 - 51 - 12, (54 - 31) / 2, 51, 31);
    [row addSubview:sw];
    return row;
}

- (UIView *)infoRowWithKey:(NSString *)key value:(NSString *)value y:(CGFloat)y width:(CGFloat)w {
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

- (void)tabChanged {
    NSInteger i = self.tabControl.selectedSegmentIndex;
    self.dumpTab.hidden = (i != 0);
    self.settingsTab.hidden = (i != 1);
    self.aboutTab.hidden = (i != 2);
    UIView *show = (i == 0) ? self.dumpTab : (i == 1) ? self.settingsTab : self.aboutTab;
    show.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ show.alpha = 1; }];
}

- (void)settingChanged:(UISwitch *)sw {
    switch (sw.tag) {
        case 1: self.dumpEnabled = sw.on; break;
        case 2: self.dumpObjC = sw.on; break;
        case 3: self.dumpSymtab = sw.on; break;
        case 4: self.dumpIl2cpp = sw.on; break;
        case 5: self.dumpExportRaw = sw.on; break;
        case 6: self.dumpFull = sw.on; break;
    }
    [self saveSettings];
}

- (void)sizeChanged:(UISegmentedControl *)seg {
    self.sizeMode = seg.selectedSegmentIndex;
    [self saveSettings];
    [self rebuildPanel];
}

- (void)togglePanel {
    BOOL show = self.panel.hidden;
    self.panel.hidden = NO;
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

- (void)dragPanel:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.floatWindow];
    CGPoint c = self.panel.center;
    c.x += t.x; c.y += t.y;
    CGRect b = self.floatWindow.bounds;
    CGFloat m = 60;
    CGFloat hw = self.panel.bounds.size.width / 2, hh = self.panel.bounds.size.height / 2;
    c.x = MAX(hw - (self.panel.bounds.size.width - m), MIN(b.size.width - hw + (self.panel.bounds.size.width - m), c.x));
    c.y = MAX(hh - (self.panel.bounds.size.height - m), MIN(b.size.height - hh + (self.panel.bounds.size.height - m), c.y));
    self.panel.center = c;
    [pan setTranslation:CGPointZero inView:self.floatWindow];
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

- (void)dumpAgain {
    if (self.dumping) return;
    dispatch_async(dispatch_get_main_queue(), ^{ self.logView.text = @""; });
    [self startDump];
}

- (void)exportFiles {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSString *docs = [self docsDir];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in @[@"dump.cs", @"ZheeOffsets.txt", @"global-metadata.dat", @"UnityFramework"]) {
        NSString *p = [docs stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:p]) [urls addObject:[NSURL fileURLWithPath:p]];
    }
    if (urls.count == 0) {
        [self log:@"Chưa có file để xuất — bấm Dump lại trước"];
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
        UIViewController *host = self.floatWindow.rootViewController;
        if (host) {
            [host presentViewController:picker animated:YES completion:nil];
            [self log:@"Đã mở trình chọn — chọn thư mục Tải về"];
        } else {
            [self log:@"Không mở được trình chọn thư mục"];
        }
    });
}

- (void)deleteFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [self docsDir];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:@"dump.cs"] error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:@"ZheeOffsets.txt"] error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:@"global-metadata.dat"] error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:@"UnityFramework"] error:nil];
    [self log:@"Đã xóa file dump (dump.cs, ZheeOffsets.txt, global-metadata.dat, UnityFramework)"];
}

// ---------------------------------------------------------------------------
// Dump
// ---------------------------------------------------------------------------
- (void)startDump {
    if (self.dumping) return;
    self.dumping = YES;
    self.il2cppDone = NO;
    [self setStatus:@"Đang chạy…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        @try {
            for (int attempt = 0; attempt < 5; attempt++) {
                if (attempt > 0) [self log:@"il2cpp chưa sẵn, thử lại lần %d…", attempt + 1];
                [self runDump];
                if (self.il2cppDone) break;
                if (attempt < 4) [NSThread sleepForTimeInterval:2.0];
            }
            [self setStatus:@"Xong!"];
        } @catch (NSException *e) {
            [self log:@"Lỗi: %@", e];
            [self setStatus:@"Lỗi"];
        }
        self.dumping = NO;
    });
}

- (NSString *)docsDir {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

- (void)runDump {
    @autoreleasepool {
        g_fullOffset = self.dumpFull;
        [self setProgress:0];
        long skippedObjC = 0, badIl2cpp = 0;
        uint32_t imgCount = _dyld_image_count();
        NSString *exePath = [NSString stringWithUTF8String:_dyld_get_image_name(0) ?: ""];
        [self log:@"Bắt đầu dump: %@", NSBundle.mainBundle.bundleIdentifier ?: @"?"];
        [self log:@"Executable: %@", exePath];
        [self log:@"Đã load %u image", imgCount];
        ZheeBuildImageCache(imgCount);
        ZheeBuildBundleFlags(NSBundle.mainBundle.bundlePath, imgCount);

        // ---- ZheeOffsets.txt: images + ObjC + Mach-O symbols + metadata ----
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"# ZheeOffsetDump v4\n# bundle: %@\n# executable: %@\n# offset = address - base cua image chua no (khong phu thuoc ASLR)\n",
                          NSBundle.mainBundle.bundleIdentifier ?: @"?", exePath];
        [out appendFormat:@"# --- loaded images (framework + binary) ---\n"];
        for (uint32_t i = 0; i < imgCount; i++) {
            uintptr_t b = 0, e = 0;
            ZheeImageRange(i, &b, &e);
            const char *name = _dyld_get_image_name(i);
            [out appendFormat:@"# [%u] base=0x%lx size=0x%lx %s\n", i,
                              (unsigned long)b, (unsigned long)(e - b), name ? name : "?"];
        }

        // ObjC theo image (mac dinh chi app bundle; Full offset = ca image).
        [out appendFormat:@"\n# --- ObjC per-image (%@) ---\n", g_fullOffset ? @"full: ca image" : @"chi image trong app bundle"];
        NSMutableArray<NSMutableString *> *perImage = [NSMutableArray array];
        for (uint32_t i = 0; i < imgCount; i++) [perImage addObject:[NSMutableString string]];
        long totalObjCClasses = 0, totalObjCMethods = 0;
        int clsCount = self.dumpObjC ? objc_getClassList(NULL, 0) : 0;
        if (clsCount > 0) {
            __unsafe_unretained Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * (size_t)clsCount);
            clsCount = objc_getClassList(classes, clsCount);
            qsort(classes, (size_t)clsCount, sizeof(Class), cmpClassNames);
            for (int ci = 0; ci < clsCount; ci++) {
                if (ci % 500 == 0) {
                    [self log:@"ObjC: %d/%d class…", ci, clsCount];
                    [self setProgress:0.05f + 0.40f * (float)ci / (float)(clsCount > 0 ? clsCount : 1)];
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
                    qsort(methods, mcount, sizeof(Method), cmpMethodNames);
                    for (unsigned int mi = 0; mi < mcount; mi++) {
                        uintptr_t addr = (uintptr_t)method_getImplementation(methods[mi]);
                        int img = ZheeImageContaining(addr, imgCount);
                        if (img < 0) { skippedObjC++; continue; }
                        if (g_imgInBundle && !g_imgInBundle[img]) continue; // bo method cua system framework
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
        if (self.dumpObjC) [self log:@"ObjC xong: %ld classes, %ld methods", totalObjCClasses, totalObjCMethods];
        else [self log:@"ObjC: TẮT (theo cài đặt)"];
        [self setProgress:0.45f];

        // Mach-O symbols (C/C++) — mac dinh chi app bundle, Full offset = ca image.
        [out appendFormat:@"\n# --- Mach-O symbols (C/C++) - %@ ---\n", g_fullOffset ? @"ca image" : @"image trong app bundle"];
        NSString *bundlePath = NSBundle.mainBundle.bundlePath;
        if (!self.dumpSymtab) [self log:@"Symbols: TẮT (theo cài đặt)"];
        for (uint32_t ii = 0; ii < imgCount && self.dumpSymtab; ii++) {
            [self setProgress:0.45f + 0.15f * (float)ii / (float)(imgCount > 0 ? imgCount : 1)];
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
            [self log:@"Symbol %@: %u symbols", imgPath.lastPathComponent, nsyms];
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
                if (keptSyms % 20000 == 0) [self log:@"  symbol %@: %ld…", imgPath.lastPathComponent, keptSyms];
            }
            [out appendFormat:@"# symtab [%u]: %ld symbols dinh nghia\n", ii, keptSyms];
        }

        // Metadata file.
        [self setProgress:0.60f];
        [out appendFormat:@"\n# --- metadata (global-metadata.dat) ---\n"];
        NSString *metaPath = nil;
        NSArray<NSString *> *candidates = @[
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"],
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Metadata/global-metadata.dat"],
        ];
        NSString *frameworksDir = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
        NSArray *fw = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksDir error:nil];
        NSMutableArray *allCandidates = [candidates mutableCopy];
        for (NSString *f in fw ?: @[]) {
            if ([f containsString:@"Unity"]) {
                [allCandidates addObject:[frameworksDir stringByAppendingPathComponent:[f stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"]]];
            }
        }
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
                [out appendFormat:@"# sanity: 0x%x (mong doi 0xfab11baf)\n# metadata version: %u\n", u32[0], u32[1]];
                [out appendFormat:@"# stringLiteralCount: %u, stringCount: %u\n", u32[3], u32[7]];
            }
            [self log:@"Metadata: %@ (%llu bytes)", metaPath.lastPathComponent, fsize];
        } else {
            [out appendFormat:@"# khong tim thay global-metadata.dat\n"];
            [self log:@"Không tìm thấy global-metadata.dat"];
        }

        // Export file goc cho Il2CppDumper tren PC: global-metadata.dat + binary UnityFramework.
        if (!self.dumpExportRaw) [self log:@"Xuất file gốc: TẮT (theo cài đặt)"];
        if (self.dumpExportRaw && metaPath) {
            NSString *metaDest = [[self docsDir] stringByAppendingPathComponent:@"global-metadata.dat"];
            [fm removeItemAtPath:metaDest error:nil];
            NSError *copyErr = nil;
            if ([fm copyItemAtPath:metaPath toPath:metaDest error:&copyErr]) {
                [self log:@"Đã xuất global-metadata.dat -> Documents"];
            } else {
                [self log:@"Copy global-metadata.dat lỗi: %@", copyErr];
            }
        }
        NSString *ufPath = nil;
        NSString *ufDirect = [frameworksDir stringByAppendingPathComponent:@"UnityFramework.framework/UnityFramework"];
        if ([fm fileExistsAtPath:ufDirect]) {
            ufPath = ufDirect;
        } else {
            NSDirectoryEnumerator *ufe = [fm enumeratorAtPath:frameworksDir];
            int ufGuard = 0;
            for (NSString *p in ufe) {
                if (++ufGuard > 5000) break;
                if ([p.lastPathComponent isEqualToString:@"UnityFramework"]) {
                    ufPath = [frameworksDir stringByAppendingPathComponent:p];
                    break;
                }
            }
        }
        if (self.dumpExportRaw && ufPath) {
            NSString *ufDest = [[self docsDir] stringByAppendingPathComponent:@"UnityFramework"];
            [fm removeItemAtPath:ufDest error:nil];
            NSError *ufErr = nil;
            if ([fm copyItemAtPath:ufPath toPath:ufDest error:&ufErr]) {
                unsigned long long usz = [[fm attributesOfItemAtPath:ufDest error:nil][NSFileSize] unsignedLongLongValue];
                [self log:@"Đã xuất UnityFramework (%llu bytes) -> Documents", usz];
            } else {
                [self log:@"Copy UnityFramework lỗi: %@", ufErr];
            }
        } else {
            [self log:@"Không tìm thấy UnityFramework binary"];
        }

        [self setProgress:0.65f];
        NSString *offsetsPath = [[self docsDir] stringByAppendingPathComponent:@"ZheeOffsets.txt"];
        NSError *err = nil;
        [out writeToFile:offsetsPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) [self log:@"Ghi ZheeOffsets.txt lỗi: %@", err];
        else [self log:@"Đã xuất ZheeOffsets.txt"];

        // ---- dump.cs (il2cpp, kiểu Il2CppDumper) ----
        NSMutableString *cs = [NSMutableString string];
        [cs appendFormat:@"// Dumped by ZheeOffsetDump\n// Bundle: %@\n// Date: %@\n// RVA = offset (VA - imageBase)\n\n",
                         NSBundle.mainBundle.bundleIdentifier ?: @"?", [NSDate date]];
        FnDomainGet domainGet = (FnDomainGet)ZheeSym("il2cpp_domain_get");
        if (!self.dumpIl2cpp) {
            [cs appendFormat:@"// il2cpp: tat theo cai dat\n"];
            [self log:@"il2cpp: TẮT (theo cài đặt)"];
            self.il2cppDone = YES;
        } else if (!domainGet) {
            [cs appendFormat:@"// Khong phai app Unity (khong co il2cpp_domain_get)\n"];
            [self log:@"Không phải app Unity — dump.cs chỉ có header"];
            self.il2cppDone = YES;
        } else {
            Il2CppDomain *domain = domainGet();
            if (!domain) {
                [cs appendFormat:@"// il2cpp chua khoi tao\n"];
                [self log:@"il2cpp chưa khởi tạo"];
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
                FnMethodParamName paramName = (FnMethodParamName)ZheeSym("il2cpp_method_get_param_name");
                FnFieldName fieldName = (FnFieldName)ZheeSym("il2cpp_field_get_name");
                FnFieldOffset fieldOffset = (FnFieldOffset)ZheeSym("il2cpp_field_get_offset");
                FnFieldType fieldType = (FnFieldType)ZheeSym("il2cpp_field_get_type");
                FnTypeName typeName = (FnTypeName)ZheeSym("il2cpp_type_get_name");
                FnFree il2cppFree = (FnFree)ZheeSym("il2cpp_free");
                if (!assembliesFn || !assemblyImage || !getClass || !classMethods || !className) {
                    [cs appendFormat:@"// Thieu il2cpp API (khong dump duoc)\n"];
                    [self log:@"Thiếu il2cpp API"];
                    self.il2cppDone = YES;
                } else {
                    size_t asmCount = 0;
                    const Il2CppAssembly **asms = assembliesFn(domain, &asmCount);
                    long totalClasses = 0, totalMethods = 0, totalFields = 0;
                    for (size_t ai = 0; ai < asmCount; ai++) {
                        const Il2CppImage *img = assemblyImage(asms[ai]);
                        if (!img) continue;
                        const char *asmName = imageName ? (imageName(img) ?: "?") : "?";
                        [cs appendFormat:@"// Image: %s\n", asmName];
                        [self log:@"Dump il2cpp: %s", [NSString stringWithUTF8String:asmName]];
                        [self setProgress:0.65f + 0.35f * (float)ai / (float)(asmCount > 0 ? asmCount : 1)];
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
                                    int imgIdx = ZheeImageContaining((uintptr_t)mp, imgCount);
                                    if (imgIdx < 0) badIl2cpp++;
                                    uintptr_t b = 0, e = 0;
                                    if (imgIdx >= 0) ZheeImageRange((uint32_t)imgIdx, &b, &e);
                                    unsigned long rva = imgIdx >= 0 ? (unsigned long)((uintptr_t)mp - b) : 0;
                                    [bucket appendFormat:@"\t\tpublic %@; // 0x%lx\n", sig, rva];
                                    totalMethods++;
                                }
                            }
                            [bucket appendFormat:@"\t}\n\n"];
                            totalClasses++;
                            if (totalClasses % 500 == 0) [self log:@"  il2cpp: %ld classes…", totalClasses];
                        }
                        // Xuất namespace đã sắp xếp.
                        NSArray *sortedNs = [nsOrder sortedArrayUsingSelector:@selector(compare:)];
                        for (NSString *ns in sortedNs) {
                            [cs appendFormat:@"namespace %@\n{\n%@}\n\n", ns, nsBuckets[ns]];
                        }
                    }
                    [cs appendFormat:@"// Tong: %ld classes, %ld methods, %ld fields\n", totalClasses, totalMethods, totalFields];
                    [self log:@"il2cpp xong: %ld classes, %ld methods, %ld fields", totalClasses, totalMethods, totalFields];
                    self.il2cppDone = YES;
                }
            }
        }
        NSString *csPath = [[self docsDir] stringByAppendingPathComponent:@"dump.cs"];
        [cs writeToFile:csPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err) [self log:@"Ghi dump.cs lỗi: %@", err];
        else [self log:@"Đã xuất dump.cs -> %@", csPath];
        [self setProgress:1.0f];
        if (skippedObjC == 0 && badIl2cpp == 0) [self log:@"Kiểm tra: tất cả offset nằm trong image — chính xác"];
        else [self log:@"Kiểm tra: ObjC bỏ qua %ld method, il2cpp %ld method ngoài image", skippedObjC, badIl2cpp];
        NSMutableArray *doneFiles = [NSMutableArray array];
        [doneFiles addObject:@"ZheeOffsets.txt"];
        if (self.dumpIl2cpp) [doneFiles addObject:@"dump.cs"];
        if (self.dumpExportRaw) { [doneFiles addObject:@"global-metadata.dat"]; [doneFiles addObject:@"UnityFramework"]; }
        [self log:@"HOÀN TẤT. Documents: %@", [doneFiles componentsJoinedByString:@", "]];
    }
}

@end

__attribute__((constructor)) static void ZheeOffsetDumpInit(void) {
    // Delay ngan 1–2s (lech timing, tranh fingerprint), roi hien panel + chay dump.
    double delay = 1.0 + (double)arc4random_uniform(1000) / 1000.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try { [[ZheeOffsetDump shared] setup]; } @catch (NSException *e) {}
    });
}
