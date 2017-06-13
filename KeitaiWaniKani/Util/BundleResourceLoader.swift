//
//  BundleResourceLoader.swift
//  AlliCrab
//
//  Copyright © 2016 Chris Laverty. All rights reserved.
//

import Foundation

protocol BundleResourceLoader {
    func loadBundleResource(name: String, withExtension: String, javascriptEncode: Bool) -> String
}

extension BundleResourceLoader {
    func loadBundleResource(name: String, withExtension: String, javascriptEncode: Bool) -> String {
        guard let scriptURL = Bundle.main.url(forResource: name, withExtension: withExtension) else {
            fatalError("Count not find resource \(name).\(withExtension) in main bundle")
        }
        
        let contents = try! String(contentsOf: scriptURL)
        return javascriptEncode ? encodeForJavascript(contents) : contents
    }
    
    private func encodeForJavascript(_ string: String) -> String {
        return string.unicodeScalars.map { $0.escaped(asASCII: false) }.joined(separator: "")
    }
}
