#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
@interface NativeTextView : NSTextView <IMKTextInput>
@property BOOL hidesSurroundingText;
@property NSUInteger markedLineBreaks;
@property BOOL sendsOnReturn;
@property NSUInteger returnEvents;
@property NSUInteger lastReturnModifiers;
@property BOOL receivedReturnWithMarkedText;
@property(copy) NSString *lastSubmittedText;
- (void)setMarkedText:(id)string selectionRange:(NSRange)selectionRange replacementRange:(NSRange)replacementRange;
- (NSString *)stringFromRange:(NSRange)range actualRange:(NSRangePointer)actualRange;
@end
