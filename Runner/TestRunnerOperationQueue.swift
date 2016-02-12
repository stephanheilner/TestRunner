//
//  TestRunnerOperationQueue.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/16/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
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
        if isWaitingToLoad() {
            let waitOperation = WaitOperation()
            waitOperations.append(waitOperation)
            operation.addDependency(waitOperation)
        }
        super.addOperation(operation)
    }
    
    private func isWaitingToLoad() -> Bool {
        for case let operation as TestRunnerOperation in operations where !operation.loaded {
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
