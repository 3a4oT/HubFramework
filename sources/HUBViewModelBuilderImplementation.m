#import "HUBViewModelBuilderImplementation.h"

#import "HUBViewModelImplementation.h"
#import "HUBComponentModelBuilderImplementation.h"
#import "HUBComponentModelImplementation.h"
#import "HUBComponentIdentifier.h"
#import "HUBJSONSchema.h"
#import "HUBViewModelJSONSchema.h"
#import "HUBComponentModelJSONSchema.h"
#import "HUBJSONPath.h"

#import "HUBContentProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface HUBViewModelBuilderImplementation ()

@property (nonatomic, strong, readonly) id<HUBJSONSchema> JSONSchema;
@property (nonatomic, copy, readonly) NSString *defaultComponentNamespace;
@property (nonatomic, strong, readonly) HUBComponentModelBuilderImplementation *headerComponentModelBuilderImplementation;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, HUBComponentModelBuilderImplementation *> *bodyComponentModelBuilders;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *bodyComponentIdentifierOrder;

@end

@implementation HUBViewModelBuilderImplementation

@synthesize viewIdentifier = _viewIdentifier;
@synthesize featureIdentifier = _featureIdentifier;
@synthesize entityIdentifier = _entityIdentifier;
@synthesize navigationBarTitle = _navigationBarTitle;
@synthesize extensionURL = _extensionURL;
@synthesize customData = _customData;

- (instancetype)initWithFeatureIdentifier:(NSString *)featureIdentifier
                               JSONSchema:(id<HUBJSONSchema>)JSONSchema
                defaultComponentNamespace:(NSString *)defaultComponentNamespace
{
    NSParameterAssert(featureIdentifier != nil);
    NSParameterAssert(JSONSchema != nil);
    NSParameterAssert(defaultComponentNamespace != nil);
    
    self = [super init];
    
    if (self) {
        _JSONSchema = JSONSchema;
        _defaultComponentNamespace = [defaultComponentNamespace copy];
        _viewIdentifier = [NSUUID UUID].UUIDString;
        _featureIdentifier = [featureIdentifier copy];
        _headerComponentModelBuilderImplementation = [[HUBComponentModelBuilderImplementation alloc] initWithModelIdentifier:@"header"
                                                                                                           featureIdentifier:featureIdentifier
                                                                                                                  JSONSchema:_JSONSchema
                                                                                                   defaultComponentNamespace:defaultComponentNamespace];
        
        _bodyComponentModelBuilders = [NSMutableDictionary new];
        _bodyComponentIdentifierOrder = [NSMutableArray new];
    }
    
    return self;
}

#pragma mark - HUBViewModelBuilder

- (id<HUBComponentModelBuilder>)headerComponentModelBuilder
{
    return self.headerComponentModelBuilderImplementation;
}

- (nullable NSError *)addJSONData:(NSData *)JSONData
{
    NSError *error;
    NSObject *JSONObject = [NSJSONSerialization JSONObjectWithData:JSONData options:NSJSONReadingAllowFragments error:&error];
    
    if (error != nil || JSONObject == nil) {
        return error;
    }
    
    if ([JSONObject isKindOfClass:[NSDictionary class]]) {
        [self addDataFromJSONDictionary:(NSDictionary *)JSONObject];
    } else if ([JSONObject isKindOfClass:[NSArray class]]) {
        [self addDataFromJSONArray:(NSArray *)JSONObject usingSchema:self.JSONSchema];
    } else {
        return [NSError errorWithDomain:@"spotify.com.hubFramework.invalidJSON" code:0 userInfo:nil];
    }
    
    return nil;
}

- (BOOL)builderExistsForBodyComponentModelWithIdentifier:(NSString *)identifier
{
    return self.bodyComponentModelBuilders[identifier] != nil;
}

- (id<HUBComponentModelBuilder>)builderForBodyComponentModelWithIdentifier:(NSString *)identifier
{
    return [self getOrCreateBuilderForBodyComponentModelWithIdentifier:identifier];
}

- (void)removeBuilderForBodyComponentModelWithIdentifier:(NSString *)identifier
{
    [self.bodyComponentModelBuilders removeObjectForKey:identifier];
    [self.bodyComponentIdentifierOrder removeObject:identifier];
}

#pragma mark - API

- (BOOL)isEmpty
{
    if (![self headerComponentModelBuilderIsConsideredEmpty]) {
        return NO;
    }
    
    if (self.bodyComponentModelBuilders.count > 0) {
        return NO;
    }
    
    return YES;
}

- (HUBViewModelImplementation *)build
{
    HUBComponentModelImplementation *headerComponentModel;
    
    if (![self headerComponentModelBuilderIsConsideredEmpty]) {
        headerComponentModel = [self.headerComponentModelBuilderImplementation buildForIndex:0];
    } else {
        headerComponentModel = nil;
    }
    
    NSArray * const bodyComponentModels = [HUBComponentModelBuilderImplementation buildComponentModelsUsingBuilders:self.bodyComponentModelBuilders
                                                                                                    identifierOrder:self.bodyComponentIdentifierOrder];
    
    return [[HUBViewModelImplementation alloc] initWithIdentifier:self.viewIdentifier
                                                featureIdentifier:self.featureIdentifier
                                                 entityIdentifier:self.entityIdentifier
                                               navigationBarTitle:self.navigationBarTitle
                                             headerComponentModel:headerComponentModel
                                              bodyComponentModels:[bodyComponentModels copy]
                                                     extensionURL:self.extensionURL
                                                       customData:[self.customData copy]];
}

#pragma mark - HUBJSONCompatibleBuilder

- (void)addDataFromJSONDictionary:(NSDictionary<NSString *, NSObject *> *)dictionary
{
    id<HUBViewModelJSONSchema> const viewModelSchema = self.JSONSchema.viewModelSchema;
    
    NSString * const viewIdentifier = [viewModelSchema.identifierPath stringFromJSONDictionary:dictionary];
    
    if (viewIdentifier != nil) {
        self.viewIdentifier = viewIdentifier;
    }
    
    NSString * const featureIdentifier = [viewModelSchema.featureIdentifierPath stringFromJSONDictionary:dictionary];
    
    if (featureIdentifier != nil) {
        self.featureIdentifier = featureIdentifier;
    }
    
    NSString * const entityIdentifier = [viewModelSchema.entityIdentifierPath stringFromJSONDictionary:dictionary];
    
    if (entityIdentifier != nil) {
        self.entityIdentifier = entityIdentifier;
    }
    
    NSString * const navigationBarTitle = [viewModelSchema.navigationBarTitlePath stringFromJSONDictionary:dictionary];
    
    if (navigationBarTitle != nil) {
        self.navigationBarTitle = navigationBarTitle;
    }
    
    NSURL * const extensionURL = [viewModelSchema.extensionURLPath URLFromJSONDictionary:dictionary];
    
    if (extensionURL != nil) {
        self.extensionURL = extensionURL;
    }
    
    NSDictionary * const customData = [viewModelSchema.customDataPath dictionaryFromJSONDictionary:dictionary];
    
    if (customData != nil) {
        NSDictionary * const existingCustomData = self.customData;
        
        if (existingCustomData != nil) {
            NSMutableDictionary * const mutableCustomData = [existingCustomData mutableCopy];
            [mutableCustomData addEntriesFromDictionary:customData];
            self.customData = [mutableCustomData copy];
        } else {
            self.customData = customData;
        }
    }
    
    NSDictionary * const headerComponentModelDictionary = [viewModelSchema.headerComponentModelDictionaryPath dictionaryFromJSONDictionary:dictionary];
    
    if (headerComponentModelDictionary != nil) {
        [self.headerComponentModelBuilderImplementation addDataFromJSONDictionary:headerComponentModelDictionary];
    }
    
    NSArray * const bodyComponentModelDictionaries = [viewModelSchema.bodyComponentModelDictionariesPath valuesFromJSONDictionary:dictionary];
    
    for (NSDictionary * const componentModelDictionary in bodyComponentModelDictionaries) {
        [self addDataFromBodyComponentModelJSONDictionary:componentModelDictionary];
    }
}

#pragma mark - Private utilities

- (void)addDataFromJSONArray:(NSArray<NSObject *> *)array usingSchema:(id<HUBJSONSchema>)schema
{
    for (NSObject * const object in array) {
        if ([object isKindOfClass:[NSDictionary class]]) {
            [self addDataFromBodyComponentModelJSONDictionary:(NSDictionary *)object];
        }
    }
}

- (void)addDataFromBodyComponentModelJSONDictionary:(NSDictionary<NSString *, NSObject *> *)dictionary
{
    NSString * const identifier = [self.JSONSchema.componentModelSchema.identifierPath stringFromJSONDictionary:dictionary];
    HUBComponentModelBuilderImplementation * const builder = [self getOrCreateBuilderForBodyComponentModelWithIdentifier:identifier];
    [builder addDataFromJSONDictionary:dictionary];
}

- (HUBComponentModelBuilderImplementation *)getOrCreateBuilderForBodyComponentModelWithIdentifier:(nullable NSString *)identifier
{
    if (identifier != nil) {
        NSString * const existingBuilderIdentifier = identifier;
        HUBComponentModelBuilderImplementation * const existingBuilder = self.bodyComponentModelBuilders[existingBuilderIdentifier];
        
        if (existingBuilder != nil) {
            return existingBuilder;
        }
    }
    
    HUBComponentModelBuilderImplementation * const newBuilder = [[HUBComponentModelBuilderImplementation alloc] initWithModelIdentifier:identifier
                                                                                                                      featureIdentifier:self.featureIdentifier
                                                                                                                             JSONSchema:self.JSONSchema
                                                                                                              defaultComponentNamespace:self.defaultComponentNamespace];
    
    [self.bodyComponentModelBuilders setObject:newBuilder forKey:newBuilder.modelIdentifier];
    [self.bodyComponentIdentifierOrder addObject:newBuilder.modelIdentifier];
    
    return newBuilder;
}

- (BOOL)headerComponentModelBuilderIsConsideredEmpty
{
    return self.headerComponentModelBuilder.componentName == nil;
}

@end

NS_ASSUME_NONNULL_END
