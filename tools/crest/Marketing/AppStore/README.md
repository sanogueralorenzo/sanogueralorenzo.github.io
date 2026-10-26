# Crest iOS App Store listing

[listing/en-US.json](listing/en-US.json) is the maintained English listing copy for iPhone and iPad: name, subtitle, promotional text, keywords, description, What's New, URLs, and primary category.

## Update the listing

Update the copy to reflect shipped capabilities and review What's New against the build being submitted. Keep the name and subtitle within 30 characters each, promotional text within 170 characters, keywords within 100 bytes, and description and What's New within 4,000 characters each.

Copy the version-specific fields into the iOS version in App Store Connect. The name, subtitle, and category are under App Information; the privacy policy URL is under App Privacy. Saving listing changes, selecting a release build, and submitting for review are separate steps.

## Screenshot guidance

Keep raw captures, artwork generation tools, and exported images outside the repository. Use real app screens from the showcase session (`CREST_SHOWCASE_SESSION=1`): Work with Lion and Personal with Winter. Where the address shows, load the hosted demo pages at `crestbrowser.com/demos/source/` and `/demos/trail/` instead of the showcase's `data:` pages.

The iPhone order is Spaces, Crest Studio, the tab archive, Appearance, and Private Browsing. The iPad order is Spaces, Split View as columns beside each other, Crest Studio, Appearance, and Private Browsing.

Export opaque PNGs at 1320 × 2868 for the iPhone 6.9-inch slot and 2064 × 2752 for the iPad 13-inch slot (portrait, because the simulator can't be rotated without the pointer). Check the order after uploading, since concurrent uploads may finish out of order. Check Media Manager for older custom sets that would override the new images on smaller displays.

## Header and search results

The product page header is 3840 × 1646 (21:9) and the search results card is 3840 × 2560 (3:2). Check both in App Store Connect's Preview:

- iPhone shows the header's full height, cropped to about 3:2 around the centre, with the back and share buttons over the top corners.
- iPad shows it full width but cropped to about 10:3 around the middle, losing roughly the top 250 and bottom 250 pixels, with the floating tab bar over the top centre. Keep crests and text inside that band and clear of the tab bar.
- Search results show the whole card under the app's row, at about a tenth of its width, so its text must stay large.

Creative assets may show brand and mood rather than the app in use, but can't carry prices, URLs, awards, or other companies' marks.

See Apple's [product page guidance](https://developer.apple.com/app-store/product-page/), [asset best practices](https://developer.apple.com/app-store/asset-best-practices/), and [current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) when preparing a new set.
