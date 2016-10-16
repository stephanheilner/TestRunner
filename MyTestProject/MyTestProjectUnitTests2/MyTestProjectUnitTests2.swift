//
//  MyTestProjectTests.swift
//  MyTestProjectTests
//
//  Created by Stephan Heilner on 12/4/15.
//  Copyright © 2015 Test, Inc. All rights reserved.
//

import XCTest
@testable import MyTestProject

class MyTestProjectTests: XCTestCase {
    let LoopCount = 1
    
    func slowTest(_ name: String) {
        for _ in 0..<LoopCount {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
    
    func test101() {
        slowTest("test101")
    }
    
    func test102() {
        slowTest("test102")
    }
    
    func test103() {
        slowTest("test103")
        XCTAssertTrue(false, "Force this to fail")
    }
    
    func test104() {
        slowTest("test104")
    }
    
    func test105() {
        slowTest("test105")
    }
    
    func test106() {
        slowTest("test106")
    }
    
    func test107() {
        slowTest("test107")
    }
    
    func test108() {
        slowTest("test108")
    }
    
    func test109() {
        slowTest("test109")
    }
    
    func test110() {
        slowTest("test110")
    }
    
    func test111() {
        slowTest("test111")
    }
    
    func test112() {
        slowTest("test112")
    }
    
    func test113() {
        slowTest("test113")
    }
    
    func test114() {
        slowTest("test114")
    }
    
    func test115() {
        slowTest("test115")
    }
    
    func test116() {
        slowTest("test116")
    }
    
    func test117() {
        slowTest("test117")
    }
    
    func test118() {
        slowTest("test118")
    }
    
    func test119() {
        slowTest("test119")
    }
    
    func test120() {
        slowTest("test120")
    }
    
    func test121() {
        slowTest("test121")
    }
    
    func test122() {
        slowTest("test122")
    }
    
    func test123() {
        slowTest("test123")
    }
    
    func test124() {
        slowTest("test124")
    }
    
    func test125() {
        slowTest("test125")
    }
    
    func test126() {
        slowTest("test126")
    }
    
    func test127() {
        slowTest("test127")
    }
    
    func test128() {
        slowTest("test128")
    }
    
    func test129() {
        slowTest("test129")
    }
    
    func test130() {
        slowTest("test130")
    }
    
}
