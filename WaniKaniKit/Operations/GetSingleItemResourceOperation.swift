//
//  GetSingleItemResourceOperation.swift
//  KeitaiWaniKani
//
//  Copyright © 2015 Chris Laverty. All rights reserved.
//

import Foundation
import CocoaLumberjack
import FMDB
import OperationKit

/// A composite `Operation` to both download and parse resource data.
public class GetSingleItemResourceOperation<Coder: protocol<ResourceHandler, JSONDecoder, SingleItemDatabaseCoder>>: GroupOperation, NSProgressReporting {
    
    // MARK: - Properties
    
    public let progress: NSProgress = {
        let progress = NSProgress(totalUnitCount: 2)
        return progress
        }()
    
    public private(set) var downloadOperation: DownloadResourceOperation?
    public private(set) var parseOperation: ParseSingleItemOperation<Coder>?
    public var fetchRequired: Bool {
        guard let downloadOperation = downloadOperation else { return false }
        return !downloadOperation.cancelled
    }
    
    private let coder: Coder
    private let resolver: ResourceResolver
    private let databaseQueue: FMDatabaseQueue
    private let networkObserver: OperationObserver?
    private lazy var cacheFile: NSURL = {
        let tempDirectory = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return tempDirectory.URLByAppendingPathComponent("\(self.resource)/\(NSUUID().UUIDString).json")
        }()
    
    private let resource: Resource
    
    // MARK: - Initialisers
    
    public init(coder: Coder, resolver: ResourceResolver, databaseQueue: FMDatabaseQueue, networkObserver: OperationObserver?) {
        self.resource = coder.resource
        self.coder = coder
        self.resolver = resolver
        self.databaseQueue = databaseQueue
        self.networkObserver = networkObserver
        
        super.init(operations: [])
        progress.localizedDescription = "Fetching \(resource)"
        progress.localizedAdditionalDescription = "Waiting..."
        progress.cancellationHandler = { self.cancel() }
        addObserver(BlockObserver { _ in
            guard self.downloadOperation != nil else { return }
            self.progress.localizedAdditionalDescription = "Finishing..."
            
            do {
                DDLogDebug("Cleaning up cache file \(self.cacheFile)")
                try NSFileManager.defaultManager().removeItemAtURL(self.cacheFile)
            } catch NSCocoaError.FileNoSuchFileError {
                DDLogDebug("Ignoring failure to delete cache file in directory which didn't exist: \(self.cacheFile)")
            } catch {
                DDLogWarn("Failed to clean up temporary file in \(self.cacheFile): \(error)")
            }
            })
        
        name = "Get \(resource)"
    }
    
    // MARK: - Operation
    
    public override func execute() {
        progress.totalUnitCount = 2
        
        progress.becomeCurrentWithPendingUnitCount(1)
        let parseOperation = ParseSingleItemOperation(coder: coder, cacheFile: cacheFile, databaseQueue: databaseQueue)
        parseOperation.addProgressListenerForDestinationProgress(progress, localizedDescription: "Parsing \(resource)")
        parseOperation.addCondition(NoCancelledDependencies())
        progress.resignCurrent()
        self.parseOperation = parseOperation
        
        progress.becomeCurrentWithPendingUnitCount(1)
        let downloadOperation = DownloadResourceOperation(resolver: resolver, resource: resource, destinationFileURL: cacheFile, networkObserver: networkObserver)
        downloadOperation.addProgressListenerForDestinationProgress(progress, localizedDescription: "Downloading \(resource)")
        progress.resignCurrent()
        self.downloadOperation = downloadOperation
        
        // These operations must be executed in order
        parseOperation.addDependency(downloadOperation)
        
        addOperation(downloadOperation)
        addOperation(parseOperation)
        
        // This must be done last as it starts the internal queue
        super.execute()
    }
    
    public override func operationDidFinish(operation: NSOperation, withErrors errors: [ErrorType]) {
        if errors.isEmpty {
            DDLogDebug("\(operation.self.dynamicType) finished with no errors")
        } else {
            DDLogWarn("\(operation.self.dynamicType) finished with \(errors.count) error(s): \(errors)")
        }
    }
    
    public override func finished(errors: [ErrorType]) {
        super.finished(errors)
        
        // Ensure progress is 100%
        progress.completedUnitCount = progress.totalUnitCount
    }
    
}
