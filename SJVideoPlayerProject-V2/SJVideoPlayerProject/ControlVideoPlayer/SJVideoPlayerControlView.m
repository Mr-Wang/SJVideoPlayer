//
//  SJVideoPlayerControlView.m
//  SJVideoPlayerProject
//
//  Created by BlueDancer on 2017/11/29.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import "SJVideoPlayerControlView.h"
#import "SJVideoPlayerBottomControlView.h"
#import <Masonry/Masonry.h>
#import "SJVideoPlayer.h"
#import <SJObserverHelper/NSObject+SJObserverHelper.h>
#import "SJVideoPlayerSettings.h"
#import "SJVideoPlayer+UpdateSetting.h"
#import "SJVideoPlayerDraggingProgressView.h"
#import "UIView+SJVideoPlayerSetting.h"
#import <SJSlider/SJSlider.h>
#import "SJVideoPlayerLeftControlView.h"
#import "SJVideoPlayerTopControlView.h"
#import "SJVideoPlayerPreviewView.h"
#import "SJVideoPlayerMoreSettingsView.h"
#import "SJVideoPlayerMoreSettingSecondaryView.h"
#import "SJMoreSettingsSlidersViewModel.h"
#import "SJVideoPlayerMoreSetting+SJControlAdd.h"
#import "SJVideoPlayerMoreSettingSecondary.h"
#import <SJLoadingView/SJLoadingView.h>
#import <objc/message.h>

typedef NS_ENUM(NSUInteger, SJDisappearType) {
    SJDisappearType_Transform = 1 << 0,
    SJDisappearType_Alpha = 1 << 1,
    SJDisappearType_All = 1 << 2,
};

NS_ASSUME_NONNULL_BEGIN
@interface UIView (SJControlAdd)

@property (nonatomic, assign) SJDisappearType disappearType;

@property (nonatomic, assign) CGAffineTransform disappearTransform;

@property (nonatomic, assign) BOOL appearState; // appear is `YES`, disappear is `NO`.

- (void)appear;

- (void)disappear;

@end
NS_ASSUME_NONNULL_END

@implementation UIView (SJControlAdd)

- (void)setDisappearTransform:(CGAffineTransform)disappearTransform {
    objc_setAssociatedObject(self, @selector(disappearTransform), [NSValue valueWithCGAffineTransform:disappearTransform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGAffineTransform)disappearTransform {
    return [(NSValue *)objc_getAssociatedObject(self, _cmd) CGAffineTransformValue];
}

- (void)setDisappearType:(SJDisappearType)disappearType {
    objc_setAssociatedObject(self, @selector(disappearType), @(disappearType), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (SJDisappearType)disappearType {
    return [objc_getAssociatedObject(self, _cmd) integerValue];
}

- (void)setAppearState:(BOOL)appearState {
    objc_setAssociatedObject(self, @selector(appearState), @(appearState), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)appearState {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)appear {
    [self __changeState:YES];
}

- (void)disappear {
    [self __changeState:NO];
}

- (void)__changeState:(BOOL)show {
    
    if ( SJDisappearType_All == (self.disappearType & SJDisappearType_All) ) {
        self.disappearType = SJDisappearType_Alpha | SJDisappearType_Transform;
    }
    
    if ( SJDisappearType_Transform == (self.disappearType & SJDisappearType_Transform) ) {
        if ( show ) {
            self.transform = CGAffineTransformIdentity;
        }
        else {
            self.transform = self.disappearTransform;
        }
    }
    
    if ( SJDisappearType_Alpha == (self.disappearType & SJDisappearType_Alpha) ) {
        if ( show ) {
            self.alpha = 1;
        }
        else {
            self.alpha = 0.001;
        }
    }
    self.appearState = show;
}

@end


#pragma mark -

NS_ASSUME_NONNULL_BEGIN
@interface SJVideoPlayerControlView ()<SJVideoPlayerControlDelegate, SJVideoPlayerControlDataSource, SJVideoPlayerLeftControlViewDelegate, SJVideoPlayerBottomControlViewDelegate, SJVideoPlayerTopControlViewDelegate, SJVideoPlayerPreviewViewDelegate>

@property (nonatomic, assign) BOOL initialized;
@property (nonatomic, assign) BOOL hasBeenGeneratedPreviewImages;
@property (nonatomic, strong) SJMoreSettingsSlidersViewModel *footerViewModel;

@property (nonatomic, strong, readonly) SJVideoPlayerPreviewView *previewView;
@property (nonatomic, strong, readonly) SJVideoPlayerDraggingProgressView *draggingProgressView;
@property (nonatomic, strong, readonly) SJVideoPlayerTopControlView *topControlView;
@property (nonatomic, strong, readonly) SJVideoPlayerLeftControlView *leftControlView;
@property (nonatomic, strong, readonly) SJVideoPlayerBottomControlView *bottomControlView;
@property (nonatomic, strong, readonly) SJSlider *bottomSlider;
@property (nonatomic, strong, readonly) SJVideoPlayerMoreSettingsView *moreSettingsView;
@property (nonatomic, strong, readonly) SJVideoPlayerMoreSettingSecondaryView *moreSecondarySettingView;
@property (nonatomic, strong, readonly) SJLoadingView *loadingView;

@property (nonatomic, strong, readwrite, nullable) NSArray<SJVideoPlayerMoreSetting *> *moreSettings;

@end
NS_ASSUME_NONNULL_END

@implementation SJVideoPlayerControlView {
    BOOL _controlLayerAppearedState;
}

@synthesize previewView = _previewView;
@synthesize draggingProgressView = _draggingProgressView;
@synthesize topControlView = _topControlView;
@synthesize leftControlView = _leftControlView;
@synthesize bottomControlView = _bottomControlView;
@synthesize bottomSlider = _bottomSlider;
@synthesize moreSettingsView = _moreSettingsView;
@synthesize moreSecondarySettingView = _moreSecondarySettingView;
@synthesize footerViewModel = _footerViewModel;
@synthesize loadingView = _loadingView;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if ( !self ) return nil;
    [self _controlViewSetupView];
    [self _controlViewLoadSetting];
    [self _controlViewInstallNotifications];
    // default values
    _generatePreviewImages = YES;
    return self;
}

- (void)setVideoPlayer:(SJVideoPlayer *)videoPlayer {
    if ( _videoPlayer == videoPlayer ) return;
    _videoPlayer = videoPlayer;
    dispatch_async(dispatch_get_main_queue(), ^{
        _videoPlayer.controlViewDelegate = self;
        _videoPlayer.controlViewDataSource = self;
        [_videoPlayer sj_addObserver:self forKeyPath:@"state"];
        self.moreSettings = _videoPlayer.moreSettings;
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ( [keyPath isEqualToString:@"state"] ) {
        switch ( _videoPlayer.state ) {
            case SJVideoPlayerPlayState_Prepare: {

            }
                break;
            case SJVideoPlayerPlayState_Paused:
            case SJVideoPlayerPlayState_PlayFailed:
            case SJVideoPlayerPlayState_PlayEnd: {
                self.bottomControlView.playState = NO;
            }
                break;
            case SJVideoPlayerPlayState_Playing: {
                self.bottomControlView.playState = YES;
            }
                break;
            default:
                break;
        }
    }
}

#pragma mark -

- (void)_controlViewInstallNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoPlayerSetMoreSettings:) name:SJVideoPlayerSetMoreSettingsNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)videoPlayerSetMoreSettings:(NSNotification *)notifi {
    self.moreSettings = notifi.object;
}

#pragma mark - setup views
- (void)_controlViewSetupView {
    
    [self addSubview:self.topControlView];
    [self addSubview:self.leftControlView];
    [self addSubview:self.bottomControlView];
    [self addSubview:self.draggingProgressView];
    [self addSubview:self.bottomSlider];
    [self addSubview:self.previewView];
    [self addSubview:self.moreSettingsView];
    [self addSubview:self.moreSecondarySettingView];
    [self addSubview:self.loadingView];
    
    [_topControlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.leading.trailing.offset(0);
    }];
    
    [_leftControlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.leading.offset(0);
        make.centerY.offset(0);
    }];
    
    [_bottomControlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.leading.bottom.trailing.offset(0);
    }];
    
    [_draggingProgressView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.offset(0);
    }];
    
    [_bottomSlider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.leading.bottom.trailing.offset(0);
        make.height.offset(1);
    }];
    
    [_previewView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_topControlView.mas_bottom);
        make.leading.trailing.offset(0);
    }];
    
    [_moreSettingsView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.trailing.offset(0);
        make.size.mas_offset(_moreSettingsView.intrinsicContentSize);
    }];
    
    [_moreSecondarySettingView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(_moreSettingsView);
    }];
    
    [_loadingView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.offset(0);
    }];

    [self _setControlViewsDisappearType];
    [self _setControlViewsDisappearValue];
    
    [_bottomSlider disappear];
    [_draggingProgressView disappear];
    [_topControlView disappear];
    [_leftControlView disappear];
    [_bottomControlView disappear];
    [_previewView disappear];
    [_moreSettingsView disappear];
    [_moreSecondarySettingView disappear];
}

- (void)_setControlViewsDisappearType {
    _topControlView.disappearType = SJDisappearType_Transform;
    _leftControlView.disappearType = SJDisappearType_Transform;
    _bottomControlView.disappearType = SJDisappearType_Transform;
    _bottomSlider.disappearType = SJDisappearType_Alpha;
    _previewView.disappearType = SJDisappearType_All;
    _moreSettingsView.disappearType = SJDisappearType_Transform;
    _moreSecondarySettingView.disappearType = SJDisappearType_Transform;
    _draggingProgressView.disappearType = SJDisappearType_Alpha;
}

- (void)_setControlViewsDisappearValue {
    _topControlView.disappearTransform = CGAffineTransformMakeTranslation(0, -_topControlView.intrinsicContentSize.height);
    _leftControlView.disappearTransform = CGAffineTransformMakeTranslation(-_leftControlView.intrinsicContentSize.width, 0);
    _bottomControlView.disappearTransform = CGAffineTransformMakeTranslation(0, _bottomControlView.intrinsicContentSize.height);
    _previewView.disappearTransform = CGAffineTransformMakeScale(1, 0.001);
    _moreSettingsView.disappearTransform = CGAffineTransformMakeTranslation(_moreSettingsView.intrinsicContentSize.width, 0);
    _moreSecondarySettingView.disappearTransform = CGAffineTransformMakeTranslation(_moreSecondarySettingView.intrinsicContentSize.width, 0);
}

#pragma mark - 预览视图
- (SJVideoPlayerPreviewView *)previewView {
    if ( _previewView ) return _previewView;
    _previewView = [SJVideoPlayerPreviewView new];
    _previewView.delegate = self;
    _previewView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    return _previewView;
}

- (void)previewView:(SJVideoPlayerPreviewView *)view didSelectItem:(id<SJVideoPlayerPreviewInfo>)item {
    CMTimeShow(item.localTime);
    __weak typeof(self) _self = self;
    [_videoPlayer seekToTime:item.localTime completionHandler:^(BOOL finished) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        [self.videoPlayer play];
    }];
}

#pragma mark - 拖拽视图
- (SJVideoPlayerDraggingProgressView *)draggingProgressView {
    if ( _draggingProgressView ) return _draggingProgressView;
    _draggingProgressView = [SJVideoPlayerDraggingProgressView new];
    [_draggingProgressView setPreviewImage:[UIImage imageNamed:@"placeholder"]];
    return _draggingProgressView;
}

#pragma mark - 顶部视图
- (SJVideoPlayerTopControlView *)topControlView {
    if ( _topControlView ) return _topControlView;
    _topControlView = [SJVideoPlayerTopControlView new];
    _topControlView.delegate = self;
    return _topControlView;
}

- (BOOL)hasBeenGeneratedPreviewImages {
    return _hasBeenGeneratedPreviewImages;
}

- (void)topControlView:(SJVideoPlayerTopControlView *)view clickedBtnTag:(SJVideoPlayerTopViewTag)tag {
    switch ( tag ) {
        case SJVideoPlayerTopViewTag_Back: {
            if ( _videoPlayer.isFullScreen ) [_videoPlayer rotation];
            else {
                if ( [self.delegate respondsToSelector:@selector(clickedBackBtnOnControlView:)] ) {
                    [self.delegate clickedBackBtnOnControlView:self];
                }
            }
        }
            break;
        case SJVideoPlayerTopViewTag_More: {
            [self controlLayerNeedDisappear:self.videoPlayer];
            [UIView animateWithDuration:0.3 animations:^{
                [self.moreSettingsView appear];
            }];
        }
            break;
        case SJVideoPlayerTopViewTag_Preview: {
            [UIView animateWithDuration:0.3 animations:^{
                if ( !self.previewView.appearState ) [self.previewView appear];
                else [self.previewView disappear];
            }];
        }
            break;
    }
}

#pragma mark - 左侧视图
- (SJVideoPlayerLeftControlView *)leftControlView {
    if ( _leftControlView ) return _leftControlView;
    _leftControlView = [SJVideoPlayerLeftControlView new];
    _leftControlView.delegate = self;
    return _leftControlView;
}

- (void)leftControlView:(SJVideoPlayerLeftControlView *)view clickedBtnTag:(SJVideoPlayerLeftViewTag)tag {
    switch ( tag ) {
        case SJVideoPlayerLeftViewTag_Lock: {
            self.videoPlayer.locked = NO;  // 点击锁定按钮, 解锁
        }
            break;
        case SJVideoPlayerLeftViewTag_Unlock: {
            self.videoPlayer.locked = YES; // 点击解锁按钮, 锁定
        }
            break;
    }
    view.lockState = self.videoPlayer.locked;
}


#pragma mark - 底部视图
- (SJVideoPlayerBottomControlView *)bottomControlView {
    if ( _bottomControlView ) return _bottomControlView;
    _bottomControlView = [SJVideoPlayerBottomControlView new];
    _bottomControlView.delegate = self;
    return _bottomControlView;
}

- (void)bottomView:(SJVideoPlayerBottomControlView *)view clickedBtnTag:(SJVideoPlayerBottomViewTag)tag {
    switch ( tag ) {
        case SJVideoPlayerBottomViewTag_Play: {
            if ( self.videoPlayer.state == SJVideoPlayerPlayState_PlayEnd ) [self.videoPlayer replay];
            else [self.videoPlayer play];
        }
            break;
        case SJVideoPlayerBottomViewTag_Pause: {
            [self.videoPlayer pause];
        }
            break;
        case SJVideoPlayerBottomViewTag_Full: {
            [self.videoPlayer rotation];
        }
            break;
    }
}

- (SJSlider *)bottomSlider {
    if ( _bottomSlider ) return _bottomSlider;
    _bottomSlider = [SJSlider new];
    _bottomSlider.pan.enabled = NO;
    _bottomSlider.trackHeight = 1;
    return _bottomSlider;
}


#pragma mark - 一级`更多`视图
- (SJVideoPlayerMoreSettingsView *)moreSettingsView {
    if ( _moreSettingsView ) return _moreSettingsView;
    _moreSettingsView = [SJVideoPlayerMoreSettingsView new];
    _moreSettingsView.footerViewModel = self.footerViewModel;
    return _moreSettingsView;
}

- (SJMoreSettingsSlidersViewModel *)footerViewModel {
    if ( _footerViewModel ) return _footerViewModel;
    _footerViewModel = [SJMoreSettingsSlidersViewModel new];
    
    __weak typeof(self) _self = self;
    _footerViewModel.initialBrightnessValue = ^float{
        __strong typeof(_self) self = _self;
        if ( !self ) return 0;
        return self.videoPlayer.brightness;
    };
    
    _footerViewModel.initialVolumeValue = ^float{
        __strong typeof(_self) self = _self;
        if ( !self ) return 0;
        return self.videoPlayer.volume;
    };
    
    _footerViewModel.initialPlayerRateValue = ^float{
        __strong typeof(_self) self = _self;
        if ( !self ) return 1;
        return self.videoPlayer.rate;
    };
    
    _footerViewModel.needChangeVolume = ^(float volume) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.videoPlayer.volume = volume;
    };
    
    _footerViewModel.needChangeBrightness = ^(float brightness) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.videoPlayer.brightness = brightness;
    };
    
    _footerViewModel.needChangePlayerRate = ^(float rate) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.videoPlayer.rate = rate;
    };
    return _footerViewModel;
}

- (void)setMoreSettings:(NSArray<SJVideoPlayerMoreSetting *> *)moreSettings {
    if ( moreSettings == _moreSettings ) return;
    _moreSettings = moreSettings;
    NSMutableSet<SJVideoPlayerMoreSetting *> *moreSettingsM = [NSMutableSet new];
    [moreSettings enumerateObjectsUsingBlock:^(SJVideoPlayerMoreSetting * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self _addSetting:obj container:moreSettingsM];
    }];
    [moreSettingsM enumerateObjectsUsingBlock:^(SJVideoPlayerMoreSetting * _Nonnull obj, BOOL * _Nonnull stop) {
        [self _dressSetting:obj];
    }];
    
    self.moreSettingsView.moreSettings = moreSettings;
}

- (void)_addSetting:(SJVideoPlayerMoreSetting *)setting container:(NSMutableSet<SJVideoPlayerMoreSetting *> *)moreSttingsM {
    [moreSttingsM addObject:setting];
    if ( !setting.showTowSetting ) return;
    [setting.twoSettingItems enumerateObjectsUsingBlock:^(SJVideoPlayerMoreSettingSecondary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self _addSetting:(SJVideoPlayerMoreSetting *)obj container:moreSttingsM];
    }];
}

- (void)_dressSetting:(SJVideoPlayerMoreSetting *)setting {
    if ( !setting.clickedExeBlock ) return;
    __weak typeof(self) _self = self;
    if ( setting.isShowTowSetting ) {
        setting._exeBlock = ^(SJVideoPlayerMoreSetting * _Nonnull setting) {
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            [UIView animateWithDuration:0.3 animations:^{
                [self.moreSettingsView disappear];
                [self.moreSecondarySettingView appear];
            }];
            self.moreSecondarySettingView.twoLevelSettings = setting;
            setting.clickedExeBlock(setting);
        };
    }
    else {
        setting._exeBlock = ^(SJVideoPlayerMoreSetting * _Nonnull setting) {
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            [UIView animateWithDuration:0.3 animations:^{
                [self.moreSettingsView disappear];
                [self.moreSecondarySettingView disappear];
            }];
            setting.clickedExeBlock(setting);
        };
    }
}


#pragma mark - 二级`更多`视图
- (SJVideoPlayerMoreSettingSecondaryView *)moreSecondarySettingView {
    if ( _moreSecondarySettingView ) return _moreSecondarySettingView;
    _moreSecondarySettingView = [SJVideoPlayerMoreSettingSecondaryView new];
    return _moreSecondarySettingView;
}


#pragma mark - loading 视图
- (SJLoadingView *)loadingView {
    if ( _loadingView ) return _loadingView;
    _loadingView = [SJLoadingView new];
    __weak typeof(self) _self = self;
    _loadingView.settingRecroder = [[SJVideoPlayerControlSettingRecorder alloc] initWithSettings:^(SJVideoPlayerSettings * _Nonnull setting) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.loadingView.lineColor = setting.loadingLineColor;
    }];
    return _loadingView;
}


#pragma mark - 加载配置

- (void)_controlViewLoadSetting {
    
    // load default setting
    __weak typeof(self) _self = self;
    
    // 1. load default setting
    
    //    [SJVideoPlayer loadDefaultSettingAndCompletion:^{
    //        __strong typeof(_self) self = _self;
    //        if ( !self ) return;
    //        self.initialized = YES;
    //        [self videoPlayer:self.videoPlayer controlLayerNeedAppear:YES];
    //    }];
    
    // 2. or update
    [SJVideoPlayer update:^(SJVideoPlayerSettings * _Nonnull commonSettings) {
        // update common settings
        commonSettings.more_trackColor = [UIColor whiteColor];
        commonSettings.progress_trackColor = [UIColor colorWithWhite:0.4 alpha:1];
        commonSettings.progress_bufferColor = [UIColor whiteColor];
        // .... other settings ....
        // .... .... .... .... ....
    } completion:^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.initialized = YES; // 初始化已完成, 在初始化期间不显示控制层.
        [self controlLayerNeedAppear:self.videoPlayer]; // 显示控制层
    }];
    
    
    self.settingRecroder = [[SJVideoPlayerControlSettingRecorder alloc] initWithSettings:^(SJVideoPlayerSettings * _Nonnull setting) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.bottomSlider.traceImageView.backgroundColor = setting.progress_traceColor;
        self.bottomSlider.trackImageView.backgroundColor = setting.progress_bufferColor;
        self.videoPlayer.placeholder = setting.placeholder;
    }];
}


#pragma mark - Video Player Control Data Source

- (UIView *)controlView {
    return self;
}

- (void)setControlLayerAppearedState:(BOOL)controlLayerAppearedState {
    _controlLayerAppearedState = controlLayerAppearedState;
}

- (BOOL)controlLayerAppearedState {
    return _controlLayerAppearedState;
}

- (BOOL)controlLayerAppearCondition {
    return self.initialized;                                // 在初始化期间不显示控制层
}

- (BOOL)controlLayerDisappearCondition {
    if ( self.previewView.appearState ) return NO;          // 如果预览视图显示, 则不隐藏控制层
    return YES;
}

- (BOOL)triggerGesturesCondition:(CGPoint)location {
    if ( CGRectContainsPoint(self.moreSettingsView.frame, location) ||
//         CGRectContainsPoint(self.moreSecondarySettingView.frame, location) ||
         CGRectContainsPoint(self.previewView.frame, location) ) return NO;
    return YES;
}


#pragma mark - Video Player Control Delegate

- (void)controlLayerNeedAppear:(SJVideoPlayer *)videoPlayer {
    self.topControlView.alwaysShowTitle = self.videoPlayer.URLAsset.alwaysShowTitle;
    self.topControlView.title = self.videoPlayer.URLAsset.title;
    
    [UIView animateWithDuration:0.3 animations:^{
        [_topControlView appear];
        [_bottomControlView appear];
        if ( videoPlayer.isFullScreen ) [_leftControlView appear];
        else [_leftControlView disappear];  // 如果是小屏, 则不显示锁屏按钮
        [_bottomSlider disappear];
        
        if ( _moreSettingsView.appearState ) [_moreSettingsView disappear];
        if ( _moreSecondarySettingView.appearState ) [_moreSecondarySettingView disappear];
    }];
    
    self.controlLayerAppearedState = YES;   // update state
}

- (void)controlLayerNeedDisappear:(SJVideoPlayer *)videoPlayer {
    [UIView animateWithDuration:0.3 animations:^{
        [_topControlView disappear];
        [_bottomControlView disappear];
        [_leftControlView disappear];
        [_previewView disappear];
        [_bottomSlider appear];
    }];
    
    self.controlLayerAppearedState = NO;    // update state
}

- (void)lockedVideoPlayer:(SJVideoPlayer *)videoPlayer {
    [self controlLayerNeedDisappear:videoPlayer];
    [UIView animateWithDuration:0.3 animations:^{
        [_leftControlView appear];
    }];
}

- (void)unlockedVideoPlayer:(SJVideoPlayer *)videoPlayer {
    [self controlLayerNeedAppear:videoPlayer];
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer currentTime:(NSTimeInterval)currentTime currentTimeStr:(nonnull NSString *)currentTimeStr totalTime:(NSTimeInterval)totalTime totalTimeStr:(nonnull NSString *)totalTimeStr {
    [self.bottomControlView setCurrentTimeStr:currentTimeStr totalTimeStr:totalTimeStr];
    self.bottomControlView.progress = currentTime / totalTime;
    self.bottomSlider.value = self.bottomControlView.progress;
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer loadedTimeProgress:(float)progress {
    self.bottomControlView.bufferProgress = progress;
}

- (void)startLoading:(SJVideoPlayer *)videoPlayer {
    [self.loadingView start];
}

- (void)loadCompletion:(SJVideoPlayer *)videoPlayer {
    [self.loadingView stop];
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer willRotateView:(BOOL)isFull {
    if ( isFull && !videoPlayer.URLAsset.isM3u8 ) {
        self.draggingProgressView.style = SJVideoPlayerDraggingProgressViewStylePreviewProgress;
    }
    else {
        self.draggingProgressView.style = SJVideoPlayerDraggingProgressViewStyleArrowProgress;
    }
    
    // update layout
    self.bottomControlView.fullscreen = isFull;
    self.topControlView.fullscreen = isFull;
    
    [self _setControlViewsDisappearValue]; // update. `reset`.
    
    [self controlLayerNeedDisappear:videoPlayer];
    
    if ( _moreSettingsView.appearState ) [_moreSettingsView disappear];
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer lockStateDidChange:(BOOL)isLocked {
    self.leftControlView.lockState = isLocked;
}

- (void)horizontalDirectionWillBeginDragging:(SJVideoPlayer *)videoPlayer {
    [UIView animateWithDuration:0.25 animations:^{
        [self.draggingProgressView appear];
    }];
    
    [self.draggingProgressView setCurrentTimeStr:videoPlayer.currentTimeStr totalTimeStr:videoPlayer.totalTimeStr];
    [self controlLayerNeedDisappear:videoPlayer];
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer horizontalDirectionDidDrag:(CGFloat)translation {
    self.draggingProgressView.progress += translation;
    [self.draggingProgressView setCurrentTimeStr:[videoPlayer timeStringWithSeconds:self.draggingProgressView.progress * videoPlayer.totalTime]];
    if ( videoPlayer.isFullScreen && !videoPlayer.URLAsset.isM3u8 ) {
        NSTimeInterval secs = self.draggingProgressView.progress * videoPlayer.totalTime;
        __weak typeof(self) _self = self;
        [videoPlayer screenshotWithTime:secs size:CGSizeMake(self.draggingProgressView.frame.size.width * 2, self.draggingProgressView.frame.size.height * 2) completion:^(SJVideoPlayer * _Nonnull videoPlayer, UIImage * _Nullable image, NSError * _Nullable error) {
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            [self.draggingProgressView setPreviewImage:image];
        }];
    }
}

- (void)horizontalDirectionDidEndDragging:(SJVideoPlayer *)videoPlayer {
    [UIView animateWithDuration:0.25 animations:^{
        [self.draggingProgressView disappear];
    }];
    
    [self.videoPlayer jumpedToTime:self.draggingProgressView.progress * videoPlayer.totalTime completionHandler:^(BOOL finished) {
        [videoPlayer play];
    }];
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer presentationSize:(CGSize)size {
    if ( !self.generatePreviewImages ) return;
    CGFloat scale = size.width / size.height;
    CGSize previewItemSize = CGSizeMake(scale * self.previewView.intrinsicContentSize.height * 2, self.previewView.intrinsicContentSize.height * 2);
    __weak typeof(self) _self = self;
    [videoPlayer generatedPreviewImagesWithMaxItemSize:previewItemSize completion:^(SJVideoPlayer * _Nonnull player, NSArray<id<SJVideoPlayerPreviewInfo>> * _Nullable images, NSError * _Nullable error) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( error ) {
            NSLog(@"Generate Preview Image Failed! error: %@", error);
        }
        else {
            self.hasBeenGeneratedPreviewImages = YES;
            self.previewView.previewImages = images;
            self.topControlView.fullscreen = player.isFullScreen;
        }
    }];
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer volumeChanged:(float)volume {
    if ( _footerViewModel.volumeChanged ) _footerViewModel.volumeChanged(volume);
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer brightnessChanged:(float)brightness {
    if ( _footerViewModel.brightnessChanged ) _footerViewModel.brightnessChanged(brightness);
}

- (void)videoPlayer:(SJVideoPlayer *)videoPlayer rateChanged:(float)rate {
    [videoPlayer showTitle:[NSString stringWithFormat:@"%.0f %%", rate * 100]];
    if ( _footerViewModel.playerRateChanged ) _footerViewModel.playerRateChanged(rate);
}
@end
