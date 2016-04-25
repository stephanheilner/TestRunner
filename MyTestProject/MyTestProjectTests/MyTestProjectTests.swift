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
    
    func slowTest(name: String) {
        for _ in 0..<LoopCount {
            NSThread.sleepForTimeInterval(5)
        }
    }
    
    func test01() {
        slowTest("test01")
    }

    func test02() {
        slowTest("test02")
    }

    func test03() {
        slowTest("test03")
    }

    func test04() {
        slowTest("test04")
    }

    func test05() {
        slowTest("test05")
    }

    func test06() {
        slowTest("test06")
    }

    func test07() {
        slowTest("test07")
    }

    func test08() {
        slowTest("test08")
    }

    func test09() {
        slowTest("test09")
    }

    func test10() {
        slowTest("test10")
    }
    
    func test11() {
        slowTest("test11")
    }
    
    func test12() {
        slowTest("test12")
    }
    
    func test13() {
        slowTest("test13")
    }
    
    func test14() {
        slowTest("test14")
    }
    
    func test15() {
        slowTest("test15")
    }
    
    func test16() {
        slowTest("test16")
    }
    
    func test17() {
        slowTest("test17")
    }
    
    func test18() {
        slowTest("test18")
    }
    
    func test19() {
        slowTest("test19")
    }
    
    func test20() {
        slowTest("test20")
    }
    
    func test21() {
        slowTest("test21")
    }
    
    func test22() {
        slowTest("test22")
    }
    
    func test23() {
        slowTest("test23")
    }
    
    func test24() {
        slowTest("test24")
    }
    
    func test25() {
        slowTest("test25")
    }
    
    func test26() {
        slowTest("test26")
    }
    
    func test27() {
        slowTest("test27")
    }
    
    func test28() {
        slowTest("test28")
    }
    
    func test29() {
        slowTest("test29")
    }
    
    func test30() {
        slowTest("test30")
    }

}
