//
//  WebAddressBarView.swift
//  KeitaiWaniKani
//
//  Copyright © 2015 Chris Laverty. All rights reserved.
//

import UIKit

class WebAddressBarView: UIView {
    
    // MARK: - Properties
    
    let secureSiteIndicator: UIImageView
    let addressLabel: UILabel
    let refreshButton: UIButton
    
    private let lockImage = UIImage(named: "NavigationBarLock")
    private let stopLoadingImage = UIImage(named: "NavigationBarStopLoading")
    private let reloadImage = UIImage(named: "NavigationBarReload")
    
    private let webView: UIWebView
    
    // MARK: - Initialisers
    
    init(frame: CGRect, forWebView webView: UIWebView) {
        self.webView = webView
        secureSiteIndicator = UIImageView(image: lockImage)
        secureSiteIndicator.translatesAutoresizingMaskIntoConstraints = false
        addressLabel = UILabel()
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.setContentCompressionResistancePriority(addressLabel.contentCompressionResistancePriorityForAxis(.Horizontal) - 1, forAxis: .Horizontal)
        refreshButton = UIButton(type: .Custom)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: frame)
        
        self.layer.cornerRadius = 5
        self.opaque = false
        self.backgroundColor = UIColor(white: 0.8, alpha: 0.5)
        
        refreshButton.addTarget(self, action: "stopOrRefreshWebView:", forControlEvents: .TouchUpInside)
        
        updateUIForRequest(nil, andLoadingStatus: false)
        addSubview(secureSiteIndicator)
        addSubview(addressLabel)
        addSubview(refreshButton)
        
        let views = [
            "secureSiteIndicator": secureSiteIndicator,
            "addressLabel": addressLabel,
            "refreshButton": refreshButton
        ]
        
        NSLayoutConstraint(item: secureSiteIndicator, attribute: .CenterY, relatedBy: .Equal, toItem: self, attribute: .CenterY, multiplier: 1, constant: 0).active = true
        NSLayoutConstraint(item: addressLabel, attribute: .CenterY, relatedBy: .Equal, toItem: self, attribute: .CenterY, multiplier: 1, constant: 0).active = true
        NSLayoutConstraint(item: refreshButton, attribute: .CenterY, relatedBy: .Equal, toItem: self, attribute: .CenterY, multiplier: 1, constant: 0).active = true
        
        NSLayoutConstraint(item: addressLabel, attribute: .CenterX, relatedBy: .Equal, toItem: self, attribute: .CenterX, multiplier: 1, constant: 0).active = true
        NSLayoutConstraint.activateConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|-(>=8)-[secureSiteIndicator]-[addressLabel]-(>=8)-[refreshButton]-|", options: [], metrics: nil, views: views))
        NSLayoutConstraint.activateConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(>=4)-[addressLabel]-(>=4)-|", options: [], metrics: nil, views: views))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Update UI
    
    func stopOrRefreshWebView(sender: UIButton) {
        let loading: Bool
        if webView.loading {
            webView.stopLoading()
            loading = false
        } else {
            webView.reload()
            loading = true
        }
        updateUIForRequest(nil, andLoadingStatus: loading)
    }
    
    func updateUIForRequest(request: NSURLRequest?, andLoadingStatus loading: Bool) {
        // Padlock
        secureSiteIndicator.hidden = request?.URL?.scheme != "https"
        
        // URL
        addressLabel.text = domainForURL(request?.URL)
        
        // Stop/Reload indicator
        if loading {
            refreshButton.setImage(stopLoadingImage, forState: .Normal)
        } else {
            refreshButton.setImage(reloadImage, forState: .Normal)
        }
    }
    
    let hostPrefixesToStrip = ["m.", "www."]
    private func domainForURL(URL: NSURL?) -> String? {
        guard let host = URL?.host?.lowercaseString else {
            return nil
        }
        
        for prefix in hostPrefixesToStrip {
            if let range = host.rangeOfString(prefix, options: [.AnchoredSearch]) {
                return host.substringFromIndex(range.endIndex)
            }
        }
        return host
    }
    
}
