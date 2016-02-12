//
//  JSONObject.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/15/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Foundation

class JSONObject {
    
    class func jsonObjectFromStandardOutputData(data: NSData) -> [[String: AnyObject]]? {
        if let jsonString = String(data: data, encoding: NSUTF8StringEncoding) {
            return jsonObjectFromJSONString(jsonString)
        }
        return nil
    }
    
    class func jsonObjectFromJSONStreamFile(path: String) -> [[String: AnyObject]]? {
        do {
            let jsonString = try String(contentsOfFile: path, encoding: NSUTF8StringEncoding)
            return jsonObjectFromJSONString(jsonString)
        } catch let error as NSError {
            NSLog("Unable to create jsonObject from jsonStream: %@", error)
        }
        return nil
    }

    private class func jsonObjectFromJSONString(var jsonString: String) -> [[String: AnyObject]]? {
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
    
    class func jsonObjectFromString(string: String) -> AnyObject? {
        guard let data = string.dataUsingEncoding(NSUTF8StringEncoding) else { return nil }
        
        do {
            let jsonObject = try NSJSONSerialization.JSONObjectWithData(data, options: [])
            return jsonObject
        } catch {
        }
        
        return nil
    }
    
}
