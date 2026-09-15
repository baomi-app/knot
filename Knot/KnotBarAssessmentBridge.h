#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runtime-only bridge for the menu-bar policy API introduced in macOS 27.
/// The implementation deliberately has no link-time dependency on the private
/// framework, so Knot can safely fall back if Apple changes or removes it.
BOOL KnotBarAssessmentIsAvailable(void);

id _Nullable KnotBarAssessmentActivate(
    NSArray<NSNumber *> *allowedSystemItems,
    NSArray<NSString *> *allowedBundleIdentifiers,
    void (^completion)(NSError * _Nullable error)
);

void KnotBarAssessmentInvalidate(id _Nullable assertion);

NS_ASSUME_NONNULL_END
