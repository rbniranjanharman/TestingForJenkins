//
//  ViewController.m
//  RealtimeVideoFilter
//
//  Created by Altitude Labs on 23/12/15.
//  Copyright © 2015 Victor. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <GLKit/GLKit.h>
#import "AppDelegate.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property GLKView *videoPreviewView;
@property EAGLContext *eaglContext;
@property CGRect videoPreviewViewBounds;

@property AVCaptureDevice *videoDevice;
@property AVCaptureSession *captureSession;
@property dispatch_queue_t captureSessionQueue;
@property UILabel *lblColor;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // remove the view's background color; this allows us not to use the opaque property (self.view.opaque = NO) since we remove the background color drawing altogether
    self.view.backgroundColor = [UIColor clearColor];
    
    // setup the GLKView for video/image preview
    UIView *window = ((AppDelegate *)[UIApplication sharedApplication].delegate).window;
    _eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
   
    
    _videoPreviewView = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height-100) context:_eaglContext];
    _videoPreviewView.enableSetNeedsDisplay = NO;
    
    // because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform so that we can draw the video preview as if we were in a landscape-oriented view; if you're using the front camera and you want to have a mirrored preview (so that the user is seeing themselves in the mirror), you need to apply an additional horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
    _videoPreviewView.transform = CGAffineTransformMakeRotation(M_PI_2);
    _videoPreviewView.frame = window.bounds;

    
    self.lblColor = [[UILabel alloc]initWithFrame:CGRectMake(0,self.view.frame.size.height-30 , self.view.frame.size.width, 30)];
    [window addSubview:self.lblColor];
    self.lblColor.backgroundColor = [UIColor redColor];
    // we make our video preview view a subview of the window, and send it to the back; this makes FHViewController's view (and its UI elements) on top of the video preview, and also makes video preview unaffected by device rotation
    [window addSubview:_videoPreviewView];
    [window sendSubviewToBack:_videoPreviewView];
    window.backgroundColor = [UIColor greenColor];
    
    // bind the frame buffer to get the frame buffer width and height;
    // the bounds used by CIContext when drawing to a GLKView are in pixels (not points),
    // hence the need to read from the frame buffer's width and height;
    // in addition, since we will be accessing the bounds in another queue (_captureSessionQueue),
    // we want to obtain this piece of information so that we won't be
    // accessing _videoPreviewView's properties from another thread/queue
    [_videoPreviewView bindDrawable];
    _videoPreviewViewBounds = CGRectZero;
    _videoPreviewViewBounds.size.width = _videoPreviewView.drawableWidth;
    _videoPreviewViewBounds.size.height = _videoPreviewView.drawableHeight;
    
    
    
    
    // create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
   // _ciContext = [CIContext contextWithEAGLContext:_eaglContext options:@{kCIContextWorkingColorSpace : [NSNull null]} ];
    
    if ([[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0)
    {
        
        [self _start];
    }
    else
    {
        NSLog(@"No device with AVMediaTypeVideo");
    }
}

- (void)_start
{
    // get the input device and also validate the settings
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    AVCaptureDevicePosition position = AVCaptureDevicePositionBack;
    
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == position) {
            _videoDevice = device;
            break;
        }
    }
    
    // obtain device input
    NSError *error = nil;
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    if (!videoDeviceInput)
    {
        NSLog(@"%@", [NSString stringWithFormat:@"Unable to obtain video device input, error: %@", error]);
        return;
    }
    
    // obtain the preset and validate the preset
    NSString *preset = AVCaptureSessionPresetHigh;
    if (![_videoDevice supportsAVCaptureSessionPreset:preset])
    {
        NSLog(@"%@", [NSString stringWithFormat:@"Capture session preset not supported by video device: %@", preset]);
        return;
    }
    
    // create the capture session
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = preset;
    
    // CoreImage wants BGRA pixel format
    NSDictionary *outputSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInteger:kCVPixelFormatType_32BGRA]};
    // create and configure video data output
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoDataOutput.videoSettings = outputSettings;
    
    // create the dispatch queue for handling capture session delegate method calls
    _captureSessionQueue = dispatch_queue_create("capture_session_queue", NULL);
    [videoDataOutput setSampleBufferDelegate:self queue:_captureSessionQueue];
    
    videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    
    // begin configure capture session
    [_captureSession beginConfiguration];
    
    if (![_captureSession canAddOutput:videoDataOutput])
    {
        NSLog(@"Cannot add video data output");
        _captureSession = nil;
        return;
    }
    
    // connect the video device input and video data and still image outputs
    [_captureSession addInput:videoDeviceInput];
    [_captureSession addOutput:videoDataOutput];
    
    [_captureSession commitConfiguration];
    
    // then start everything
    [_captureSession startRunning];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event
{
    UIImage *image  = [_videoPreviewView snapshot];
    NSLog(@"Size is %@",NSStringFromCGSize(image.size));
    UITouch *touch = [touches anyObject];
//    if([touch view] == _videoPreviewView)
//    {
        CGPoint imageViewPoint = [touch locationInView:_videoPreviewView];
        float percentX = imageViewPoint.x;
       float percentY = imageViewPoint.y ;
      self.lblColor.backgroundColor =  [self getRGBAsFromImage:image atX:percentX andY:percentY count:1];
   // }
}
- (UIColor*)getRGBAsFromImage:(UIImage*)image atX:(int)xx andY:(int)yy count:(int)count{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    
    // First get the image into your data buffer
    CGImageRef imageRef = [image CGImage];
    NSUInteger width = image.size.width;//CGImageGetWidth(imageRef);
    NSUInteger height = image.size.height;//CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
    // Now your rawData contains the image data in the RGBA8888 pixel format.
    
    int byteIndex = (bytesPerRow * yy) + xx * bytesPerPixel;
    for (int ii = 0 ; ii < count ; ++ii)
    {
        CGFloat red   = (rawData[byteIndex]     * 1.0) / 255.0;
        CGFloat green = (rawData[byteIndex + 1] * 1.0) / 255.0;
        CGFloat blue  = (rawData[byteIndex + 2] * 1.0) / 255.0;
        CGFloat alpha = (rawData[byteIndex + 3] * 1.0) / 255.0;
        byteIndex += 4;
        
        UIColor *acolor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
        NSLog(@"%@",acolor);
        [result addObject:acolor];
    }
    NSLog(@"%@ result",result);
    free(rawData);
    return [result objectAtIndex:0];
}
//override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
//    let screenSize = videoView.bounds.size
//    if let touchPoint = touches.first {
//        let x = touchPoint.locationInView(videoView).y / screenSize.height
//        let y = 1.0 - touchPoint.locationInView(videoView).x / screenSize.width
//        let focusPoint = CGPoint(x: x, y: y)
//        
//        if let device = captureDevice {
//            do {
//                try device.lockForConfiguration()
//                
//                device.focusPointOfInterest = focusPoint
//                //device.focusMode = .ContinuousAutoFocus
//                device.focusMode = .AutoFocus
//                //device.focusMode = .Locked
//                device.exposurePointOfInterest = focusPoint
//                device.exposureMode = AVCaptureExposureMode.ContinuousAutoExposure
//                device.unlockForConfiguration()
//            }
//            catch {
//                // just ignore
//            }
//        }
//    }
//}
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
//    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)imageBuffer options:nil];
//    CGRect sourceExtent = sourceImage.extent;
//    
//    // Image processing
//    CIFilter * vignetteFilter = [CIFilter filterWithName:@"CIVignetteEffect"];
//    [vignetteFilter setValue:sourceImage forKey:kCIInputImageKey];
//    [vignetteFilter setValue:[CIVector vectorWithX:sourceExtent.size.width/2 Y:sourceExtent.size.height/2] forKey:kCIInputCenterKey];
//    [vignetteFilter setValue:@(sourceExtent.size.width/2) forKey:kCIInputRadiusKey];
//    CIImage *filteredImage = [vignetteFilter outputImage];
//    
//    CIFilter *effectFilter = [CIFilter filterWithName:@"CIPhotoEffectInstant"];
//    [effectFilter setValue:filteredImage forKey:kCIInputImageKey];
//    filteredImage = [effectFilter outputImage];
//    
//    
//    CGFloat sourceAspect = sourceExtent.size.width / sourceExtent.size.height;
//    CGFloat previewAspect = _videoPreviewViewBounds.size.width  / _videoPreviewViewBounds.size.height;
//    
//    // we want to maintain the aspect radio of the screen size, so we clip the video image
//    CGRect drawRect = sourceExtent;
//    if (sourceAspect > previewAspect)
//    {
//        // use full height of the video image, and center crop the width
//        drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
//        drawRect.size.width = drawRect.size.height * previewAspect;
//    }
//    else
//    {
//        // use full width of the video image, and center crop the height
//        drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
//        drawRect.size.height = drawRect.size.width / previewAspect;
//    }
//    
//    [_videoPreviewView bindDrawable];
//    
//    if (_eaglContext != [EAGLContext currentContext])
//        [EAGLContext setCurrentContext:_eaglContext];
//    
//    // clear eagl view to grey
//    glClearColor(0.5, 0.5, 0.5, 1.0);
//    glClear(GL_COLOR_BUFFER_BIT);
//    
//    // set the blend mode to "source over" so that CI will use that
//    glEnable(GL_BLEND);
//    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
//    
//    if (filteredImage)
//        [_ciContext drawImage:filteredImage inRect:_videoPreviewViewBounds fromRect:drawRect];
//    
//    [_videoPreviewView display];
}

@end
