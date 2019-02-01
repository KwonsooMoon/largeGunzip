# largeGunzip
### gunzip extension for tha `Data` type

gunzip extension for the `Data` type based on DataCompression(https://github.com/mw99/DataCompression) by Markus Wanke.

Unzipped data written directly into file, unzipping large compressed file (larger than 100MB) supported.
Progress handler and cancel handler supported with closure


#### Supported compression algorithm is:

* GZIP format (.gz files) [RFC-1952](https://www.ietf.org/rfc/rfc1952.txt)

#### Requirements
 * iOS deployment target **>= 9.0**

## Installation
largeGunzip can be installed with [CocoaPods](https://cocoapods.org). 
Insert below snippet into your Podfile. Detail CocoaPods usage can be found [here](https://guides.cocoapods.org/using/getting-started.html).
```
pod 'largeGunzip', git: 'https://github.com/KwonsooMoon/largeGunzip.git'
```
 
## Usage example
```swift
let compressedData: Data // read gzip compressed data
// gunzip is synchronous, you won't want to do it in main UI thread.
DispatchQueue.global(qos: .userInitiated).async {
  let result = data.gunzip(filePath: "absolute_path_of_unzipped_file"),
                           progress: {(progress: Double) -> Void in
                             // do some stuff with progress value. value is between 0.0 ~ 1.0
                           },
                          shouldCancel: {() -> Bool in
                            // return true when you want to stop unzip execution
                           })
  if result {
    // gunzip done successfully
  } else {
    // gunzip failed.
  }
}
```

## License


##### Apache License, Version 2.0

##### Copyright 2019, Kwonsoo Moon

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
