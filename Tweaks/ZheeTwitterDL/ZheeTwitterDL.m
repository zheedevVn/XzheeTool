// ZheeTwitterDL.m — Dylib tải video Twitter/X về Thư viện Ảnh.
//
// Inject vào app X (Twitter) qua LC_LOAD_DYLIB (sideload). Không hook
// method nào của host app — chỉ thêm 1 nút nổi + panel riêng, nên không
// phụ thuộc class nội bộ của X, ít rủi ro crash khi X cập nhật.
//
// Luồng: nút nổi (mở/đóng panel) → dán link Tweet (icon paste) → gọi
// GET https://api-zhee.vercel.app/api/mxh/twitter?<link> kèm header
// Authorization: Bearer <key> → lấy link .mp4 → tải bằng NSURLSession
// (hiện % tiến trình) → lưu vào Ảnh bằng PHPhotoLibrary.
//
// "Hỏi 1 lần thôi":
//  - Key Zhee chỉ hỏi 1 lần đầu, lưu Keychain, lần sau tự dùng.
//  - Quyền Ảnh do iOS hỏi 1 lần (dùng quyền Add-Only).
//
// Build: xcrun -sdk iphoneos clang -arch arm64 -dynamiclib -fobjc-arc
//        -miphoneos-version-min=14.0 -framework UIKit -framework
//        Foundation -framework Photos -framework Security
//        -o ZheeTwitterDL.dylib ZheeTwitterDL.m
//
// Dùng Objective-C thay vì Swift để dylib không cần Swift runtime khi inject.

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <Security/Security.h>

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

static NSString *const kZheeAPI = @"https://api-zhee.vercel.app/api/mxh/twitter";
static NSString *const kKeychainService = @"vn.zheedev.zheetwitterdl";
static NSString *const kKeychainAccount = @"zhee-key";

// ---------------------------------------------------------------------------
// Keychain: key Zhee (hỏi 1 lần, lưu vĩnh viễn tới khi user đổi)
// ---------------------------------------------------------------------------

static NSString *ZheeLoadKey(void) {
    NSDictionary *q = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : kKeychainService,
        (__bridge id)kSecAttrAccount : kKeychainAccount,
        (__bridge id)kSecReturnData : @YES,
        (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess) return nil;
    NSData *data = (__bridge_transfer NSData *)out;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static void ZheeSaveKey(NSString *key) {
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *q = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : kKeychainService,
        (__bridge id)kSecAttrAccount : kKeychainAccount,
    };
    NSDictionary *attrs = @{ (__bridge id)kSecValueData : data };
    if (SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)attrs) == errSecItemNotFound) {
        NSMutableDictionary *add = [q mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

static void ZheeDeleteKey(void) {
    NSDictionary *q = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : kKeychainService,
        (__bridge id)kSecAttrAccount : kKeychainAccount,
    };
    SecItemDelete((__bridge CFDictionaryRef)q);
}

// ---------------------------------------------------------------------------
// Tìm link video .mp4 trong JSON trả về (không phụ thuộc tên field cố định)
// ---------------------------------------------------------------------------

static NSString *ZheeFindVideoURL(id obj, NSMutableArray<NSString *> *cands) {
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)obj;
        if ([s hasPrefix:@"http"] && [s containsString:@".mp4"]) [cands addObject:s];
        return nil;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)obj) ZheeFindVideoURL(v, cands);
        return nil;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id v in [(NSDictionary *)obj allValues]) ZheeFindVideoURL(v, cands);
    }
    return nil;
}

static NSString *ZheePickBestVideoURL(NSArray<NSString *> *cands) {
    for (NSString *u in cands) if ([u containsString:@"video.twimg.com"]) return u;
    return cands.firstObject;
}

// Cửa sổ pass-through: chỉ nhận chạm khi chạm trúng nút nổi / panel,
// còn lại cho chạm xuyên qua xuống app bên dưới.
@interface ZheePassthroughWindow : UIWindow
@end
@implementation ZheePassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

// ---------------------------------------------------------------------------
// Panel + nút nổi
// ---------------------------------------------------------------------------

@interface ZheeTwitterDL : NSObject <NSURLSessionDownloadDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIWindow *floatWindow;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextField *linkField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UIView *keyRow;
@property (nonatomic, strong) UIProgressView *progressBar;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, assign) BOOL triedURLParamForm;
@end

@implementation ZheeTwitterDL

+ (instancetype)shared { static ZheeTwitterDL *s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [ZheeTwitterDL new]; }); return s; }

// --- UI helpers ---

- (UIColor *)brandBlue { return [UIColor colorWithRed:0.11 green:0.63 blue:0.95 alpha:1]; }
- (UIColor *)brandCyan { return [UIColor colorWithRed:0.00 green:0.82 blue:1.00 alpha:1]; }

- (CAGradientLayer *)gradientFor:(CGRect)bounds {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = bounds;
    g.colors = @[(__bridge id)self.brandBlue.CGColor, (__bridge id)self.brandCyan.CGColor];
    g.startPoint = CGPointMake(0, 0.5); g.endPoint = CGPointMake(1, 0.5);
    g.cornerRadius = bounds.size.height / 2;
    return g;
}

- (void)setup {
    @try {
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

        // Nút nổi: tròn, gradient, icon tải xuống, kéo thả được
        self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatButton.frame = CGRectMake(screen.size.width - size - 16, screen.size.height / 2 - size / 2, size, size);
        self.floatButton.layer.cornerRadius = size / 2;
        self.floatButton.layer.shadowColor = UIColor.blackColor.CGColor;
        self.floatButton.layer.shadowOpacity = 0.35; self.floatButton.layer.shadowRadius = 8;
        self.floatButton.layer.shadowOffset = CGSizeMake(0, 4);
        [self.floatButton.layer insertSublayer:[self gradientFor:self.floatButton.bounds] atIndex:0];
        UIImage *icon = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
        [self.floatButton setImage:icon forState:UIControlStateNormal];
        self.floatButton.tintColor = UIColor.whiteColor;
        self.floatButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.floatButton.imageEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
        [self.floatButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFloat:)];
        [self.floatButton addGestureRecognizer:pan];

        [self.floatWindow addSubview:self.floatButton];
        self.floatWindow.hidden = NO;
        [self buildPanel];
    } @catch (NSException *e) { /* Không để tweak làm crash host app */ }
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

// --- Panel ---

- (void)buildPanel {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat w = MIN(screen.size.width - 32, 340);
    CGFloat h = 340;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2, (screen.size.height - h) / 2, w, h)];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.4; self.panel.layer.shadowRadius = 20;
    self.panel.layer.shadowOffset = CGSizeMake(0, 10);
    self.panel.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.18].CGColor;
    self.panel.layer.borderWidth = 1;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    self.panel.alpha = 0;

    // Kéo để di chuyển panel (trừ khi chạm vào nút / ô nhập)
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    panelPan.delegate = self;
    [self.panel addGestureRecognizer:panelPan];
    // Chạm vùng trống để ẩn bàn phím
    UITapGestureRecognizer *tapEmpty = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapEmpty.cancelsTouchesInView = NO;
    tapEmpty.delegate = self;
    [self.panel addGestureRecognizer:tapEmpty];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = self.panel.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:blur];

    CGFloat pad = 16, y = 14;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2 - 30, 24)];
    title.text = @"Tải video X"; title.font = [UIFont boldSystemFontOfSize:19]; title.textColor = UIColor.whiteColor;
    [self.panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w - 40, 12, 28, 28);
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.7];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:close];
    y += 34;

    // Ô nhập link + nút paste
    UIView *linkBox = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, 46)];
    linkBox.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.12];
    linkBox.layer.cornerRadius = 13;
    [self.panel addSubview:linkBox];

    UIImageView *linkIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"link"]];
    linkIcon.frame = CGRectMake(12, 13, 20, 20); linkIcon.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.6];
    [linkBox addSubview:linkIcon];

    self.linkField = [[UITextField alloc] initWithFrame:CGRectMake(40, 0, w - pad * 2 - 40 - 44, 46)];
    self.linkField.placeholder = @"Dán link Tweet…";
    self.linkField.textColor = UIColor.whiteColor;
    self.linkField.font = [UIFont systemFontOfSize:15];
    self.linkField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.linkField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.linkField.keyboardType = UIKeyboardTypeURL;
    self.linkField.returnKeyType = UIReturnKeyDone;
    self.linkField.delegate = self;
    self.linkField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Dán link Tweet…" attributes:@{NSForegroundColorAttributeName: [UIColor.whiteColor colorWithAlphaComponent:0.45]}];
    [linkBox addSubview:self.linkField];

    UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
    paste.frame = CGRectMake(w - pad * 2 - 40, 5, 36, 36);
    [paste setImage:[UIImage systemImageNamed:@"doc.on.clipboard"] forState:UIControlStateNormal];
    paste.tintColor = self.brandCyan;
    [paste addTarget:self action:@selector(pasteLink) forControlEvents:UIControlEventTouchUpInside];
    [linkBox addSubview:paste];
    y += 56;

    // Hàng nhập key (chỉ hiện khi chưa có key — hỏi 1 lần)
    self.keyRow = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, 46)];
    self.keyRow.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.12];
    self.keyRow.layer.cornerRadius = 13;
    self.keyRow.hidden = (ZheeLoadKey() != nil);
    [self.panel addSubview:self.keyRow];

    UIImageView *keyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key.fill"]];
    keyIcon.frame = CGRectMake(12, 13, 20, 20); keyIcon.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.6];
    [self.keyRow addSubview:keyIcon];

    self.keyField = [[UITextField alloc] initWithFrame:CGRectMake(40, 0, w - pad * 2 - 40 - 44, 46)];
    self.keyField.placeholder = @"Nhập Zhee key (1 lần)";
    self.keyField.textColor = UIColor.whiteColor;
    self.keyField.font = [UIFont systemFontOfSize:15];
    self.keyField.secureTextEntry = YES;
    self.keyField.delegate = self;
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Nhập Zhee key (1 lần)" attributes:@{NSForegroundColorAttributeName: [UIColor.whiteColor colorWithAlphaComponent:0.45]}];
    [self.keyRow addSubview:self.keyField];

    UIButton *saveKey = [UIButton buttonWithType:UIButtonTypeSystem];
    saveKey.frame = CGRectMake(w - pad * 2 - 40, 5, 36, 36);
    [saveKey setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateNormal];
    saveKey.tintColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
    [saveKey addTarget:self action:@selector(saveKeyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.keyRow addSubview:saveKey];
    y += 56;

    // Nút tải
    self.downloadButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.downloadButton.frame = CGRectMake(pad, y, w - pad * 2, 48);
    self.downloadButton.layer.cornerRadius = 24;
    [self.downloadButton.layer insertSublayer:[self gradientFor:self.downloadButton.bounds] atIndex:0];
    [self.downloadButton setTitle:@"Tải video" forState:UIControlStateNormal];
    self.downloadButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.downloadButton];
    y += 60;

    // % tiến trình (to, rõ) + thanh tiến trình
    self.percentLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, 32)];
    self.percentLabel.text = @"0%"; self.percentLabel.font = [UIFont boldSystemFontOfSize:28];
    self.percentLabel.textColor = UIColor.whiteColor; self.percentLabel.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:self.percentLabel];
    y += 36;

    self.progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressBar.frame = CGRectMake(pad, y, w - pad * 2, 4);
    self.progressBar.progressTintColor = self.brandCyan;
    self.progressBar.trackTintColor = [UIColor.whiteColor colorWithAlphaComponent:0.2];
    self.progressBar.progress = 0;
    [self.panel addSubview:self.progressBar];
    y += 16;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w - pad * 2, 20)];
    self.statusLabel.text = @"Dán link rồi bấm Tải video";
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.7];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:self.statusLabel];
    y += 28;

    // Đổi key (nhỏ, dưới cùng)
    UIButton *changeKey = [UIButton buttonWithType:UIButtonTypeSystem];
    changeKey.frame = CGRectMake(pad, y, w - pad * 2, 20);
    [changeKey setTitle:@"Đổi Zhee key" forState:UIControlStateNormal];
    changeKey.titleLabel.font = [UIFont systemFontOfSize:12];
    [changeKey setTitleColor:[UIColor.whiteColor colorWithAlphaComponent:0.5] forState:UIControlStateNormal];
    [changeKey addTarget:self action:@selector(changeKeyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:changeKey];

    [self.floatWindow addSubview:self.panel];
}

- (void)togglePanel {
    [self.floatWindow endEditing:YES];
    BOOL show = self.panel.hidden;
    self.panel.hidden = NO;
    [UIView animateWithDuration:0.25 animations:^{
        self.panel.alpha = show ? 1 : 0;
        self.panel.transform = show ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL f) { self.panel.hidden = !show; }];
    if (show && ZheeLoadKey() == nil) { self.keyRow.hidden = NO; [self.keyField becomeFirstResponder]; }
}

// Kéo panel + ẩn bàn phím
- (void)dragPanel:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.floatWindow];
    CGPoint c = self.panel.center;
    c.x += t.x; c.y += t.y;
    CGRect b = self.floatWindow.bounds;
    CGFloat m = 60; // luôn chừa 60pt panel trong màn hình để không mất hút
    CGFloat hw = self.panel.bounds.size.width / 2, hh = self.panel.bounds.size.height / 2;
    c.x = MAX(hw - (self.panel.bounds.size.width - m), MIN(b.size.width - hw + (self.panel.bounds.size.width - m), c.x));
    c.y = MAX(hh - (self.panel.bounds.size.height - m), MIN(b.size.height - hh + (self.panel.bounds.size.height - m), c.y));
    self.panel.center = c;
    [pan setTranslation:CGPointZero inView:self.floatWindow];
}

- (void)dismissKeyboard { [self.panel endEditing:YES]; }

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

// Chỉ bắt đầu kéo panel khi chạm vào vùng trống (không phải nút / ô nhập)
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    CGPoint p = [g locationInView:self.panel];
    UIView *hit = [self.panel hitTest:p withEvent:nil];
    while (hit) {
        if ([hit isKindOfClass:[UIControl class]]) return NO;
        hit = hit.superview;
    }
    return YES;
}

- (void)pasteLink {
    NSString *s = UIPasteboard.generalPasteboard.string;
    if (s.length) { self.linkField.text = s; [self setStatus:@"Đã dán link"]; }
    else [self setStatus:@"Clipboard trống"];
}

- (void)saveKeyTapped {
    NSString *k = [self.keyField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!k.length) { [self setStatus:@"Chưa nhập key"]; return; }
    ZheeSaveKey(k);
    self.keyRow.hidden = YES;
    [self.keyField resignFirstResponder];
    [self setStatus:@"Đã lưu key — chỉ hỏi 1 lần"];
}

- (void)changeKeyTapped {
    ZheeDeleteKey();
    self.keyField.text = @"";
    self.keyRow.hidden = NO;
    [self.keyField becomeFirstResponder];
    [self setStatus:@"Nhập key mới"];
}

- (void)setStatus:(NSString *)s { dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = s; }); }
- (void)setProgress:(double)p {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressBar.progress = p;
        self.percentLabel.text = [NSString stringWithFormat:@"%.0f%%", p * 100];
    });
}

// --- Tải ---

- (void)downloadTapped {
    NSString *link = [self.linkField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![link containsString:@"/status/"] || (![link containsString:@"x.com/"] && ![link containsString:@"twitter.com/"])) {
        [self setStatus:@"Link chưa phải link Tweet"]; return;
    }
    NSString *key = ZheeLoadKey();
    if (!key.length) {
        self.keyRow.hidden = NO;
        [self setStatus:@"Nhập Zhee key trước (hỏi 1 lần)"];
        [self.keyField becomeFirstResponder];
        return;
    }
    [self.linkField resignFirstResponder];
    [self setStatus:@"Đang lấy link video…"];
    [self setProgress:0];
    self.triedURLParamForm = NO;
    [self fetchVideoURLForLink:link key:key];
}

- (void)fetchVideoURLForLink:(NSString *)link key:(NSString *)key {
    NSString *enc = [link stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *urlStr = self.triedURLParamForm
        ? [NSString stringWithFormat:@"%@?url=%@", kZheeAPI, enc]
        : [NSString stringWithFormat:@"%@?%@", kZheeAPI, enc];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.timeoutInterval = 30;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            // Thử dạng ?url=… nếu dạng bare query thất bại
            if (!self.triedURLParamForm) { self.triedURLParamForm = YES; [self fetchVideoURLForLink:link key:key]; return; }
            [self setStatus:@"Lỗi mạng — thử lại sau"]; return;
        }
        NSError *je = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je || !json) { [self setStatus:@"Server trả về không hợp lệ"]; return; }
        NSString *msg = [json valueForKeyPath:@"thong_bao"];
        if (msg && [msg containsString:@"Đăng nhập"]) {
            ZheeDeleteKey();
            dispatch_async(dispatch_get_main_queue(), ^{ self.keyRow.hidden = NO; });
            [self setStatus:@"Key sai / hết hạn — nhập lại"];
            return;
        }
        NSMutableArray *cands = [NSMutableArray array];
        ZheeFindVideoURL(json, cands);
        NSString *videoURL = ZheePickBestVideoURL(cands);
        if (!videoURL) {
            // Thử dạng ?url=… nếu dạng bare query không ra video
            if (!self.triedURLParamForm) { self.triedURLParamForm = YES; [self fetchVideoURLForLink:link key:key]; return; }
            [self setStatus:@"Không tìm thấy video trong Tweet này"];
            return;
        }
        [self setStatus:@"Đang tải video…"];
        [self downloadVideoFrom:videoURL];
    }] resume];
}

- (void)downloadVideoFrom:(NSString *)videoURL {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.task = [session downloadTaskWithURL:[NSURL URLWithString:videoURL]];
    [self.task resume];
}

// NSURLSessionDownloadDelegate — cập nhật % tiến trình
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite > 0) [self setProgress:(double)totalBytesWritten / (double)totalBytesExpectedToWrite];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"zhee_tweet_video.mp4"];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    NSError *e = nil;
    [[NSFileManager defaultManager] copyItemAtURL:location toURL:[NSURL fileURLWithPath:tmp] error:&e];
    if (e) { [self setStatus:@"Lỗi lưu file tạm"]; return; }
    [self setProgress:1];
    [self saveVideoToPhotos:tmp];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) [self setStatus:@"Tải thất bại — thử lại"];
}

- (void)saveVideoToPhotos:(NSString *)path {
    void (^doSave)(void) = ^{
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:path]];
        } completionHandler:^(BOOL ok, NSError *err) {
            [self setStatus:ok ? @"Đã lưu vào Ảnh ✓" : @"Lưu thất bại — thử lại"];
        }];
    };
    // Quyền Add-Only: iOS chỉ hỏi 1 lần
    if (@available(iOS 14, *)) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
            if (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited) doSave();
            else [self setStatus:@"Chưa cấp quyền Ảnh — bật trong Cài đặt"];
        }];
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus st) {
            if (st == PHAuthorizationStatusAuthorized) doSave();
            else [self setStatus:@"Chưa cấp quyền Ảnh — bật trong Cài đặt"];
        }];
    }
}

@end

// Entry point — chạy khi dylib được load vào host app
__attribute__((constructor)) static void ZheeTwitterDLInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try { [[ZheeTwitterDL shared] setup]; } @catch (NSException *e) {}
    });
}
