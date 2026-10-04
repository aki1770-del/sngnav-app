// Android's location indicator, perm_group_location.xml, from the Android
// Open Source Project: platform/frameworks/base,
// core/res/res/drawable/perm_group_location.xml. Used only by tests; nothing
// in this file is built into the app. See NOTICE beside this file.
//
// Copyright (C) 2015 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// What is taken: the two android:pathData strings, unmodified. The source
// file's fill colour and tint are not taken; a test draws the shape in its
// own colour to compare outlines.

/// The two android:pathData strings of perm_group_location.xml, unmodified:
/// an outlined pin, and the dot at its centre.
const List<String> kPermGroupLocationPathData = <String>[
  'M12,2C8.13,2 5,5.13 5,9c0,5.25 7,13 7,13s7,-7.75 7,-13C19,5.13 15.87,2 '
      '12,2zM7,9c0,-2.76 2.24,-5 5,-5s5,2.24 5,5c0,2.88 -2.88,7.19 -5,9.88'
      'C9.92,16.21 7,11.85 7,9z',
  'M12,9m-2.5,0a2.5,2.5 0,1 1,5 0a2.5,2.5 0,1 1,-5 0',
];
