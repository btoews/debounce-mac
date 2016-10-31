// compile and run from the commandline with:
//    clang -fobjc-arc -framework Cocoa  ./foo.m  -o foo
//    sudo ./foo

#import <Foundation/Foundation.h>
#import <AppKit/NSEvent.h>

typedef CFMachPortRef EventTap;

@interface KeyChanger : NSObject
{
@private
  EventTap _eventTap;
  CFRunLoopSourceRef _runLoopSource;
  CGEventRef _lastEvent;
  long long lastKeytime;
  UInt16 lastKeycode;
}
@end

CGEventRef _tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, KeyChanger* listener);

@implementation KeyChanger

- (BOOL)tapEvents
{
  if (!_eventTap) {
    NSLog(@"Initializing an event tap.");

    _eventTap = CGEventTapCreate(kCGSessionEventTap,
                                 kCGTailAppendEventTap,
                                 kCGEventTapOptionDefault,
                                 CGEventMaskBit(kCGEventKeyDown),
                                 (CGEventTapCallBack)_tapCallback,
                                 (__bridge void *)(self));
    if (!_eventTap) {
      NSLog(@"unable to create event tap. must run as root or add privlidges for assistive devices to this app.");
      return NO;
    }
  }
  CGEventTapEnable(_eventTap, TRUE);

  return [self isTapActive];
}

- (BOOL)isTapActive
{
  return CGEventTapIsEnabled(_eventTap);
}

- (void)listen
{
  if (!_runLoopSource) {
    if (_eventTap) {//dont use [self tapActive]
      _runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,
                                                     _eventTap, 0);
      // Add to the current run loop.
      CFRunLoopAddSource(CFRunLoopGetCurrent(), _runLoopSource,
                         kCFRunLoopCommonModes);

      NSLog(@"Registering event tap as run loop source.");
      CFRunLoopRun();
    }else{
      NSLog(@"No Event tap in place! You will need to call listen after tapEvents to get events.");
    }
  }
}

- (CGEventRef)processEvent:(CGEventRef)cgEvent
{
  NSEvent* event = [NSEvent eventWithCGEvent:cgEvent];
  long long currentKeytime = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
  UInt16 currentKeycode = [event keyCode];
  BOOL debounce = false;

  if (currentKeycode == lastKeycode &&
      (currentKeytime - lastKeytime) < 45) {

    NSLog(@"BOUNCE detected!!!  Letter \"%@\".", event.characters);
    NSLog(@"Time between keys: %lldms", (currentKeytime - lastKeytime));
    NSLog(@"Keycode is: %d", lastKeycode);

    // Cancel keypress event
    debounce = true;
  }

  if(debounce) {
    return NULL;
  }

  lastKeytime = currentKeytime;
  lastKeycode = currentKeycode;

  _lastEvent = [event CGEvent];
  CFRetain(_lastEvent); // must retain the event. will be released by the system

  return _lastEvent;
}

- (void)dealloc
{
  if (_runLoopSource){
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopCommonModes);
    CFRelease(_runLoopSource);
  }
  if (_eventTap){

    //kill the event tap
    CGEventTapEnable(_eventTap, FALSE);
    CFRelease(_eventTap);
  }
}

@end
CGEventRef _tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, KeyChanger* listener) {
  //Do not make the NSEvent here.
  //NSEvent will throw an exception if we try to make an event from the tap timout type
  @autoreleasepool {
    if(type == kCGEventTapDisabledByTimeout) {
      NSLog(@"event tap has timed out, re-enabling tap");
      [listener tapEvents];
      return nil;
    }
    if (type != kCGEventTapDisabledByUserInput) {
      return [listener processEvent:event];
    }
  }
  return event;
}

int main(int argc, const char * argv[])
{
  @autoreleasepool {
    KeyChanger* keyChanger = [KeyChanger new];
    [keyChanger tapEvents];
    [keyChanger listen]; //blocking call.
  }
  return 0;
}