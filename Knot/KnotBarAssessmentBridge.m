#import "KnotBarAssessmentBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static Class KnotBarConfigurationClass;
static Class KnotBarAssertionClass;
static BOOL KnotBarFrameworkLoaded;

static void KnotBarLoadFramework(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *path = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
        if (dlopen(path, RTLD_LAZY | RTLD_LOCAL) == NULL) {
            return;
        }

        KnotBarConfigurationClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        KnotBarAssertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
        KnotBarFrameworkLoaded = KnotBarConfigurationClass != Nil && KnotBarAssertionClass != Nil;
    });
}

BOOL KnotBarAssessmentIsAvailable(void) {
    KnotBarLoadFramework();
    return KnotBarFrameworkLoaded;
}

id KnotBarAssessmentActivate(NSArray<NSNumber *> *systemItems,
                             NSArray<NSString *> *bundleIdentifiers,
                             void (^completion)(NSError *error)) {
    KnotBarLoadFramework();
    if (!KnotBarFrameworkLoaded) {
        return nil;
    }

    @try {
        SEL configurationSelector = NSSelectorFromString(
            @"initWithAllowedSystemItems:allowedBundleIdentifiers:"
        );
        SEL activationSelector = NSSelectorFromString(
            @"activateWithConfiguration:completionHandler:"
        );
        if (![KnotBarConfigurationClass instancesRespondToSelector:configurationSelector] ||
            ![KnotBarAssertionClass instancesRespondToSelector:activationSelector]) {
            return nil;
        }

        id allocatedConfiguration = [KnotBarConfigurationClass alloc];
        id (*makeConfiguration)(id, SEL, id, id) = (void *)objc_msgSend;
        id configuration = makeConfiguration(
            allocatedConfiguration,
            configurationSelector,
            systemItems,
            bundleIdentifiers
        );
        if (configuration == nil) {
            return nil;
        }

        id assertion = [[KnotBarAssertionClass alloc] init];
        if (assertion == nil) {
            return nil;
        }
        // MenuBarClientCore completes on its private worker queue. Keep that
        // implementation detail out of Swift's main-actor callback.
        void (^mainQueueCompletion)(NSError *) = ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        };
        void (*activate)(id, SEL, id, void (^)(NSError *)) = (void *)objc_msgSend;
        activate(assertion, activationSelector, configuration, mainQueueCompletion);
        return assertion;
    } @catch (NSException *exception) {
        NSLog(@"Knot Bar macOS 27 compatibility unavailable: %@", exception.reason);
        return nil;
    }
}

void KnotBarAssessmentInvalidate(id assertion) {
    if (assertion == nil) {
        return;
    }

    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:selector]) {
            void (*invalidate)(id, SEL) = (void *)objc_msgSend;
            invalidate(assertion, selector);
        }
    } @catch (NSException *exception) {
        NSLog(@"Knot Bar assertion cleanup failed: %@", exception.reason);
    }
}
