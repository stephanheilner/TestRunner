//
//  TestRunnerOperationQueue.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/16/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation
import Swiftification

class TestRunnerOperationQueue: NSOperationQueue {

    static let SimulatorLoadedNotification = "SimulatorLoadedNotification"
    
    var waitOperations = [NSOperation]()
    
    override init() {
        super.init()

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "simulatorLoaded:", name: TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
    }
    
    override func addOperation(operation: NSOperation) {
        // Causing it to hang, when just one build is added it has a wait operation but it
        if isWaitingToLoad() {
            let waitOperation = WaitOperation()
            waitOperations.append(waitOperation)
            operation.addDependency(waitOperation)
        }
        super.addOperation(operation)
    }
    
    private func isWaitingToLoad() -> Bool {
        for case let operation as TestRunnerOperation in operations where !operation.simulatorLaunched {
            return true
        }
        return false
    }
    
    func simulatorLoaded(notification: NSNotification) {
        guard let waitOperation = waitOperations.shift() as? WaitOperation else { return }
        
        waitOperation.executing = false
        waitOperation.finished = true
    }
    
}
