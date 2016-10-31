//
//  XCTestCase+ListTests.swift
//  MyTestProject
//
//  Created by Stephan Heilner on 9/14/16.
//  Copyright © 2016 Test, Inc. All rights reserved.
//

import XCTest
import Foundation

extension XCTestCase {
    
    @nonobjc static let testListURL: URL? = {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "TestRunnerListTests") as? String else { return nil }
        
        print("\n************ List Tests ******************\n", path, "\n******************************\n\n\n")
        
        return URL(fileURLWithPath: path)
    }()
    
    @nonobjc static var tests: [String] = []
    
    @nonobjc static var observing = false
    
    override open class func initialize() {
        guard self === XCTestCase.self else { return }
        
        let originalSelector = #selector(invokeTest)
        let swizzledSelector = #selector(swizzled_invokeTest)
        
        let originalMethod = class_getInstanceMethod(self, originalSelector)
        let swizzledMethod = class_getInstanceMethod(self, swizzledSelector)
        
        let didAddMethod = class_addMethod(self, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        if didAddMethod {
            class_replaceMethod(self, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    func swizzled_invokeTest() {
        if XCTestCase.testListURL != nil, var testName = name {
            if !XCTestCase.observing {
                XCTestObservationCenter.shared().addTestObserver(self)
                XCTestCase.observing = true
            }
            if let range = testName.range(of: "-[") {
                testName = testName.substring(from: range.upperBound)
            }
            if let range = testName.range(of: "]") {
                testName = testName.substring(to: range.lowerBound)
            }
            let nameParts = testName.components(separatedBy: " ")
            if nameParts.count == 2, let testSuite = nameParts.first, let testName = nameParts.last {
                let testClass = NSStringFromClass(type(of: self)).replacingOccurrences(of: ("." + testSuite), with: "")
                XCTestCase.tests.append("\(testClass)/\(testSuite)/\(testName)")
            }
        } else {
            swizzled_invokeTest()
        }
    }
    
}

extension XCTestCase: XCTestObservation {
    
    public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        guard let startIndex = testSuite.name?.range(of: ".xctest")?.lowerBound, let testSuiteName = testSuite.name?.substring(to: startIndex), let fileURL = XCTestCase.testListURL else { return }
        
        do {
            let fileData = (try? Data(contentsOf: fileURL)) ?? "{}".data(using: String.Encoding.utf8)!
            var jsonObject = try JSONSerialization.jsonObject(with: fileData, options: []) as? [String: AnyObject] ?? [:]
            jsonObject[testSuiteName] = XCTestCase.tests as AnyObject
            
            _ = try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
            _ = try? jsonData.write(to: fileURL, options: .atomic)
        } catch {
            print(error)
        }
    }
}
