/*

OODeepCopy.h

Informal protocol and utility function for making efficient deep copies of
immutable collections.

It is implemented in such a way that all objects can be deep copied. Objects
that implement the NSCopying protocol are automatically copied, while others
are retained. The following special cases exist:
  * NSStrings and NSValues (including NSNumbers) are uniqued - that is, the
    resulting collection will only include one (immutable) copy of any string
    or number.
  * Arrays, sets and dictionaries deep copy their contents.

For objects where the mutable/immutable distinction exists, the result should
be expected to be immutable.

This self-optimizing behaviour is similar to that performed by binary plist
export.

NOTE: in accordance with Cocoa coding conventions, methods and functions with
Copy in the name return objects owned by the receiver.


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2009 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCocoa.h"


id OODeepCopy(id object);


@interface NSObject (OODeepCopy)

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects;

@end
