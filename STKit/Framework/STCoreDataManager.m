//
//  STCoreDataManager.m
//  STKit
//
//  Created by SunJiangting on 13-10-5.
//  Copyright (c) 2013年 SunJiangting. All rights reserved.
//

#import "STCoreDataManager.h"

#import <CoreData/CoreData.h>

@interface STCoreDataManager ()

@property(STPROPERTYNULLABLE nonatomic, copy) NSString *modelName;
@property(STPROPERTYNULLABLE nonatomic, copy) NSString *dbFilePath;

@property(nonatomic, strong) NSManagedObjectContext *writeManagedObjectContext;
@property(nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property(nonatomic, strong) NSManagedObjectContext *backgroundManagedObjectContext;

@property(nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property(nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;

- (void)managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                performBlock:(void (^)(NSManagedObjectContext *))block
           completionHandler:(void (^)(void))completionHandler;
@end

@implementation STCoreDataManager

- (void)dealloc {
    
}

- (instancetype)initWithModelName:(NSString *)modelName dbFilePath:(NSString *)path {
    self = [super init];
    if (self) {
        self.modelName = modelName;
        self.dbFilePath = path;
        [self connectData];
    }
    return self;
}

- (id)init {
    return [self initWithModelName:@"" dbFilePath:@""];
}

- (BOOL)connectData {
    return !!(self.managedObjectContext);
}

- (BOOL)saveManagedObjectContext:(NSManagedObjectContext *)managedObjectContext error:(NSError **)error {
    __block NSError *childError;
    if (![managedObjectContext obtainPermanentIDsForObjects:[[managedObjectContext insertedObjects] allObjects] error:&childError]) {
        if (childError && error) {
            *error = childError;
        }
        return NO;
    }
    __block BOOL saved = NO;
    if ([managedObjectContext hasChanges]) {
        if ([NSThread isMainThread]) {
            saved = [managedObjectContext save:&childError];
        } else {
            [managedObjectContext performBlockAndWait:^{
                saved = [managedObjectContext save:&childError];
            }];
        }
    }
    if (managedObjectContext == _writeManagedObjectContext) {
        if (childError && error) {
            *error = childError;
        }
        return saved;
    } else {
        if (!saved) {
            NSLog(@"Sth is wrong when child Managed Object Context saved.%@", childError);
            if (childError && error) {
                *error = childError;
            }
            return NO;
        } else {
            return [self saveManagedObjectContext:managedObjectContext.parentContext error:error];
        }
    }
}

#pragma mark - Save Blocks
- (void)performBlock:(void (^)(NSManagedObjectContext *))block completionHandler:(void (^)(void))completionHandler {
    [self managedObjectContext:[self dispatchManagedObjectContext] performBlock:block completionHandler:completionHandler];
}

- (void)performBlockOnMainThread:(void (^ __nonnull)(NSManagedObjectContext * __nonnull))block completionHandler:(void (^)(void))completionHandler {
    [self managedObjectContext:self.managedObjectContext performBlock:block completionHandler:completionHandler];
}

- (void)performBlockInBackground:(void (^ __nonnull)(NSManagedObjectContext * __nonnull))block completionHandler:(void (^)(void))completionHandler {
    [self managedObjectContext:self.backgroundManagedObjectContext performBlock:block completionHandler:completionHandler];
}

#pragma mark - Core Data stack

- (NSManagedObjectContext *)dispatchManagedObjectContext {
    if (!self.managedObjectContext) {
        return nil;
    }
    NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    managedObjectContext.parentContext = self.managedObjectContext;
    managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    return managedObjectContext;
}

- (NSManagedObjectContext *)backgroundManagedObjectContext {
    if (!self.managedObjectContext) {
        _backgroundManagedObjectContext = nil;
        return nil;
    }
    if (!_backgroundManagedObjectContext) {
        _backgroundManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _backgroundManagedObjectContext.parentContext = self.managedObjectContext;
        _backgroundManagedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    }
    return _backgroundManagedObjectContext;
}

- (NSManagedObjectContext *)managedObjectContext {
    if (!self.managedObjectModel || !self.writeManagedObjectContext) {
        _managedObjectContext = nil;
        return nil;
    }
    if (!_managedObjectContext) {
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        _managedObjectContext.parentContext = self.writeManagedObjectContext;
        _managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    }
    return _managedObjectContext;
}

- (NSManagedObjectContext *)writeManagedObjectContext {
    if (!self.managedObjectModel || !self.persistentStoreCoordinator) {
        _writeManagedObjectContext = nil;
        return nil;
    }
    if (!_writeManagedObjectContext) {
        _writeManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _writeManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
        _writeManagedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    }
    return _writeManagedObjectContext;
}

#pragma mark - Privete Methods

- (void)managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                performBlock:(void (^)(NSManagedObjectContext *))block
           completionHandler:(void (^)(void))completionHandler {
    if (!block) {
        if (completionHandler) {
            completionHandler();
        }
        return;
    }
    if (!managedObjectContext) {
        managedObjectContext = [self dispatchManagedObjectContext];
    }
    [managedObjectContext performBlock:^{
        block(managedObjectContext);
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler();
            });
        }
    }];
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel {
    if (_managedObjectModel) {
        return _managedObjectModel;
    }
    NSAssert(self.modelName, @"Must have a modelName before connectData");
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:self.modelName withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (!self.managedObjectModel) {
        return nil;
    }
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }
    NSURL *storeURL = [NSURL fileURLWithPath:self.dbFilePath];
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@(YES)};
    NSError *error = nil;
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    return _persistentStoreCoordinator;
}

@end

@implementation NSManagedObjectContext (STCoreDataManager)

- (NSEntityDescription *)descriptionForEntityName:(NSString *)entityName {
    return [NSEntityDescription entityForName:entityName inManagedObjectContext:self];
}

- (NSManagedObject *)entityClassFromString:(NSString *)className name:(NSString *)entityName {
    NSEntityDescription *desctiption = [self descriptionForEntityName:entityName];
    return [[NSClassFromString(className) alloc] initWithEntity:desctiption insertIntoManagedObjectContext:self];
}

@end
