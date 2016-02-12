//
//  WaitOperation.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/16/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Foundation

class WaitOperation: NSOperation {

    override var executing: Bool {
        get {
            return _executing
        }
        set {
            willChangeValueForKey("isExecuting")
            _executing = newValue
            didChangeValueForKey("isExecuting")
        }
    }
    private var _executing: Bool
    
    override var finished: Bool {
        get {
            return _finished
        }
        set {
            willChangeValueForKey("isFinished")
            _finished = newValue
            didChangeValueForKey("isFinished")
        }
    }
    private var _finished: Bool
    
    override init() {
        _executing = false
        _finished = false
        
        super.init()
    }
}
