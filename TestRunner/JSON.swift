//
//  JSON.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/15/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class JSON {
    
    class func jsonObjectFromStandardOutputData(_ data: Data) -> [[String: AnyObject]]? {
        if let jsonString = String(data: data, encoding: String.Encoding.utf8) {
            return jsonObjectFromJSONString(jsonString)
        }
        return nil
    }
    
    class func hasBeginTestSuiteEvent(_ path: String) -> Bool {
        do {
            let jsonFileContents = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            let jsonStrings = jsonFileContents.components(separatedBy: .newlines)
            for jsonString in jsonStrings {
                if let jsonData = jsonString.data(using: String.Encoding.utf8), let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: AnyObject] {
                    guard let event = jsonObject["event"] as? String, event == "begin-test-suite" else { continue }
                    return true
                }
            }
        } catch {}
        return false
    }
    
    class func jsonObjectsFromJSONStreamFile(_ path: String) -> [[String: AnyObject]]? {
        do {
            let jsonString = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            return jsonObjectFromJSONString(jsonString)
        } catch let error as NSError {
            NSLog("Unable to create jsonObject from jsonStream: %@", error)
        }
        return nil
    }

    fileprivate class func jsonObjectFromJSONString(_ jsonString: String) -> [[String: AnyObject]]? {
        var jsonString = jsonString
        do {
            jsonString.insert("[", at: jsonString.startIndex)
            jsonString += "]"
            jsonString = jsonString.replacingOccurrences(of: "}\n{", with: "},{")
            if let data = jsonString.data(using: String.Encoding.utf8) {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [[String: AnyObject]]
            }
        } catch let error as NSError {
            NSLog("Unable to create jsonObject from jsonStream: %@", error)
        }
        return nil
    }
    
}
