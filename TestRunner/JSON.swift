//
//  JSON.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/15/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class JSON {
    
    class func jsonObjectFromStandardOutputData(data: NSData) -> [[String: AnyObject]]? {
        if let jsonString = String(data: data, encoding: NSUTF8StringEncoding) {
            return jsonObjectFromJSONString(jsonString)
        }
        return nil
    }
    
    class func hasBeginTestSuiteEvent(path: String) -> Bool {
        do {
            let jsonFileContents = try String(contentsOfFile: path, encoding: NSUTF8StringEncoding)
            let jsonStrings = jsonFileContents.componentsSeparatedByCharactersInSet(.newlineCharacterSet())
            for jsonString in jsonStrings {
                if let jsonData = jsonString.dataUsingEncoding(NSUTF8StringEncoding), jsonObject = try NSJSONSerialization.JSONObjectWithData(jsonData, options: []) as? [String: AnyObject] {
                    guard let event = jsonObject["event"] as? String where event == "begin-test-suite" else { continue }
                    return true
                }
            }
        } catch {}
        return false
    }
    
    class func jsonObjectsFromJSONStreamFile(path: String) -> [[String: AnyObject]]? {
        do {
            let jsonString = try String(contentsOfFile: path, encoding: NSUTF8StringEncoding)
            return jsonObjectFromJSONString(jsonString)
        } catch let error as NSError {
            NSLog("Unable to create jsonObject from jsonStream: %@", error)
        }
        return nil
    }

    private class func jsonObjectFromJSONString(jsonString: String) -> [[String: AnyObject]]? {
        var jsonString = jsonString
        do {
            jsonString.insert("[", atIndex: jsonString.startIndex)
            jsonString += "]"
            jsonString = jsonString.stringByReplacingOccurrencesOfString("}\n{", withString: "},{")
            if let data = jsonString.dataUsingEncoding(NSUTF8StringEncoding) {
                return try NSJSONSerialization.JSONObjectWithData(data, options: []) as? [[String: AnyObject]]
            }
        } catch let error as NSError {
            NSLog("Unable to create jsonObject from jsonStream: %@", error)
        }
        return nil
    }
    
}
