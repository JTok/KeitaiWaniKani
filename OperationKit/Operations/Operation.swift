/*
Copyright (C) 2015 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
This file contains the foundational subclass of NSOperation.
*/

import Foundation
import CocoaLumberjack

/**
The subclass of `NSOperation` from which all other operations should be derived.
This class adds both Conditions and Observers, which allow the operation to define
extended readiness requirements, as well as notify many interested parties
about interesting operation state changes
*/
public class Operation: NSOperation {
    
    public let UUID = NSUUID()
    
    // use the KVO mechanism to indicate that changes to "state" affect other properties as well
    public class func keyPathsForValuesAffectingIsReady() -> Set<NSObject> {
        return ["state", "_cancelled", "isCancelled"]
    }
    
    public class func keyPathsForValuesAffectingIsExecuting() -> Set<NSObject> {
        return ["state"]
    }
    
    public class func keyPathsForValuesAffectingIsFinished() -> Set<NSObject> {
        return ["state"]
    }
    
    public class func keyPathsForValuesAffectingIsCancelled() -> Set<NSObject> {
        return ["_cancelled"]
    }
    
    // MARK: State Management
    
    enum State: Int, Comparable {
        /// The initial state of an `Operation`.
        case Initialized
        
        /// The `Operation` is ready to begin evaluating conditions.
        case Pending
        
        /// The `Operation` is evaluating conditions.
        case EvaluatingConditions
        
        /**
        The `Operation`'s conditions have all been satisfied, and it is ready
        to execute.
        */
        case Ready
        
        /// The `Operation` is executing.
        case Executing
        
        /**
        Execution of the `Operation` has finished, but it has not yet notified
        the queue of this.
        */
        case Finishing
        
        /// The `Operation` has finished executing.
        case Finished
        
        func canTransitionToState(target: State, isCancelled cancelled: Bool) -> Bool {
            switch (self, target) {
            case (.Initialized, .Pending):
                return true
            case (.Pending, .EvaluatingConditions):
                return true
            case (.Pending, .Finishing) where cancelled:
                return true
            case (.EvaluatingConditions, .Ready):
                return true
            case (.EvaluatingConditions, .Finishing) where cancelled:
                return true
            case (.Ready, .Executing):
                return true
            case (.Ready, .Finishing):
                return true
            case (.Executing, .Finishing):
                return true
            case (.Finishing, .Finished):
                return true
            default:
                return false
            }
        }
    }
    
    /**
    Indicates that the Operation can now begin to evaluate readiness conditions,
    if appropriate.
    */
    func willEnqueue() {
        state = .Pending
    }
    
    /// Private storage for the `state` property that will be KVO observed.
    private var _state = State.Initialized
    
    /// A lock to guard reads and writes to the `_state` property
    private let stateLock = NSLock()
    
    var state: State {
        get {
            return stateLock.withCriticalScope {
                _state
            }
        }
        
        set(newState) {
            /*
            It's important to note that the KVO notifications are NOT called from inside
            the lock. If they were, the app would deadlock, because in the middle of
            calling the `didChangeValueForKey()` method, the observers try to access
            properties like "isReady" or "isFinished". Since those methods also
            acquire the lock, then we'd be stuck waiting on our own lock. It's the
            classic definition of deadlock.
            */
            willChangeValueForKey("state")
            
            stateLock.withCriticalScope {
                guard _state != .Finished else {
                    return
                }
                
                assert(_state.canTransitionToState(newState, isCancelled: self.cancelled), "Performing invalid state transition.")
                _state = newState
            }
            
            didChangeValueForKey("state")
        }
    }
    
    // Here is where we extend our definition of "readiness".
    public override var ready: Bool {
        switch state {
            
        case .Initialized:
            // If the operation has been cancelled, "isReady" should return true
            return cancelled
            
        case .Pending:
            // If the operation has been cancelled, "isReady" should return true
            guard !cancelled else {
                return true
            }
            
            // If super isReady, conditions can be evaluated
            if super.ready {
                evaluateConditions()
            }
            
            // Until conditions have been evaluated, "isReady" returns false
            return false
            
        case .Ready:
            return super.ready || cancelled
            
        default:
            return false
        }
    }
    
    public var userInitiated: Bool {
        get {
            return qualityOfService == .UserInitiated
        }
        
        set {
            assert(state < .Executing, "Cannot modify userInitiated after execution has begun.")
            
            qualityOfService = newValue ? .UserInitiated : .Default
        }
    }
    
    private var _cancelled = false
    
    public override var cancelled: Bool {
        return _cancelled || super.cancelled
    }
    
    public override func cancel() {
        guard !finished else { return }
        
        _cancelled = true
        super.cancel()
    }
    
    public override var executing: Bool {
        return state == .Executing
    }
    
    public override var finished: Bool {
        return state == .Finished
    }
    
    /// A lock to guard invocations of 'evaluateConditions'
    private let conditionsLock = NSLock()
    
    private func evaluateConditions() {
        // We use a lock here since this function could be called by multiple threads since it's invoked by calls to the `ready` property.
        // We want this function to be called only once.
        guard conditionsLock.tryLock() else { return }
        defer { conditionsLock.unlock() }
        
        assert(state == .Pending && !cancelled, "evaluateConditions() was called out-of-order")
        guard state == .Pending && !cancelled else { return }
        
        state = .EvaluatingConditions
        
        OperationConditionEvaluator.evaluate(conditions, operation: self) { failures in
            DDLogVerbose("Conditions evaluated for \(self.dynamicType), errors: \(failures)")
            if !failures.isEmpty {
                self.cancelWithErrors(failures)
            }
            self.state = .Ready
        }
    }
    
    // MARK: Observers and Conditions
    
    private(set) var conditions = [OperationCondition]()
    
    public func addCondition(condition: OperationCondition) {
        assert(state < .EvaluatingConditions, "Cannot modify conditions after execution has begun.")
        
        conditions.append(condition)
    }
    
    private(set) var observers = [OperationObserver]()
    
    public func addObserver(observer: OperationObserver) {
        assert(state < .Executing, "Cannot modify observers after execution has begun.")
        
        observers.append(observer)
    }
    
    public override func addDependency(operation: NSOperation) {
        assert(state < .Executing, "Dependencies cannot be modified after execution has begun.")
        
        super.addDependency(operation)
    }
    
    // MARK: Execution and Cancellation
    
    public override final func start() {
        DDLogVerbose("Starting \(self.dynamicType)")
        
        // NSOperation.start() contains important logic that shouldn't be bypassed.
        super.start()
        
        // If the operation has been cancelled, we still need to enter the "Finished" state.
        if cancelled {
            finish()
        }
    }
    
    public override final func main() {
        assert(state == .Ready, "This operation must be performed on an operation queue.")
        
        if _internalErrors.isEmpty && !cancelled {
            DDLogVerbose("Executing \(self.dynamicType)")
            
            state = .Executing
            
            for observer in observers {
                observer.operationDidStart(self)
            }
            
            execute()
        }
        else {
            DDLogVerbose("Not executing \(self.dynamicType) due to cancellation (\(self.cancelled)) or condition errors: \(self._internalErrors)")
            finish()
        }
    }
    
    /**
    `execute()` is the entry point of execution for all `Operation` subclasses.
    If you subclass `Operation` and wish to customize its execution, you would
    do so by overriding the `execute()` method.
    
    At some point, your `Operation` subclass must call one of the "finish"
    methods defined below; this is how you indicate that your operation has
    finished its execution, and that operations dependent on yours can re-evaluate
    their readiness state.
    */
    public func execute() {
        print("\(self.dynamicType) must override `execute()`.")
        
        finish()
    }
    
    private var _internalErrors = [ErrorType]()
    public func cancelWithError(error: ErrorType? = nil) {
        if let error = error {
            cancelWithErrors([error])
        }
        else {
            cancelWithErrors()
        }
    }
    
    public func cancelWithErrors(errors: [ErrorType] = []) {
        DDLogVerbose("Cancelling \(self.dynamicType), errors: \(errors)")
        if !errors.isEmpty {
            _internalErrors.appendContentsOf(errors)
        }
        
        cancel()
    }
    
    public final func produceOperation(operation: NSOperation) {
        for observer in observers {
            observer.operation(self, didProduceOperation: operation)
        }
    }
    
    // MARK: Finishing
    
    /**
    Most operations may finish with a single error, if they have one at all.
    This is a convenience method to simplify calling the actual `finish()`
    method. This is also useful if you wish to finish with an error provided
    by the system frameworks. As an example, see `DownloadEarthquakesOperation`
    for how an error from an `NSURLSession` is passed along via the
    `finishWithError()` method.
    */
    public final func finishWithError(error: ErrorType?) {
        if let error = error {
            finish([error])
        }
        else {
            finish()
        }
    }
    
    /**
    A private property to ensure we only notify the observers once that the
    operation has finished.
    */
    private var hasFinishedAlready = false
    public final func finish(errors: [ErrorType] = []) {
        if !hasFinishedAlready {
            hasFinishedAlready = true
            state = .Finishing
            
            let combinedErrors = _internalErrors + errors
            finished(combinedErrors)
            
            DDLogVerbose("Finished \(self.dynamicType), all errors: \(combinedErrors)")
            
            for observer in observers {
                observer.operationDidFinish(self, errors: combinedErrors)
            }
            
            state = .Finished
        }
    }
    
    /**
    Subclasses may override `finished(_:)` if they wish to react to the operation
    finishing with errors. For example, the `LoadModelOperation` implements
    this method to potentially inform the user about an error when trying to
    bring up the Core Data stack.
    */
    public func finished(errors: [ErrorType]) {
        // No op.
    }
    
    public override final func waitUntilFinished() {
        /*
        Waiting on operations is almost NEVER the right thing to do. It is
        usually superior to use proper locking constructs, such as `dispatch_semaphore_t`
        or `dispatch_group_notify`, or even `NSLocking` objects. Many developers
        use waiting when they should instead be chaining discrete operations
        together using dependencies.
        
        To reinforce this idea, invoking `waitUntilFinished()` will crash your
        app, as incentive for you to find a more appropriate way to express
        the behavior you're wishing to create.
        */
        fatalError("Waiting on operations is an anti-pattern. Remove this ONLY if you're absolutely sure there is No Other Way™.")
    }
    
}

// Simple operator functions to simplify the assertions used above.
func <(lhs: Operation.State, rhs: Operation.State) -> Bool {
    return lhs.rawValue < rhs.rawValue
}

func ==(lhs: Operation.State, rhs: Operation.State) -> Bool {
    return lhs.rawValue == rhs.rawValue
}
