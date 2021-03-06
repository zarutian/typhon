# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import "bench" =~ [=> bench :Any]
import "unittest" =~ [=> unittest :Any]
exports (UTF8)

def chr(i :Int) :Char as DeepFrozen:
    return '\x00' + i


def decodeCore(var bs :Bytes, _ej) as DeepFrozen:
    var offset :Int := 0
    def buf := [].diverge()
    while (true):
        if (offset >= bs.size()):
            # End of input.
            break

        def b := bs[offset]
        if ((b & 0x80) == 0x00):
            # One byte.
            buf.push(chr(b))
            offset += 1
        else if ((b & 0xe0) == 0xc0):
            # Two bytes.
            if (bs.size() - offset < 2):
                break

            var c := (b & 0x1f) << 6
            c |= bs[offset + 1] & 0x3f
            buf.push(chr(c))
            offset += 2
        else if ((b & 0xf0) == 0xe0):
            # Three bytes.
            if (bs.size() - offset < 3):
                break

            var c := (b & 0x0f) << 12
            c |= (bs[offset + 1] & 0x3f) << 6
            c |= bs[offset + 2] & 0x3f
            buf.push(chr(c))
            offset += 3
        else if ((b & 0xf7) == 0xf0):
            # Four bytes.
            if (bs.size() - offset < 4):
                break

            var c := (b & 0x07) << 18
            c |= (bs[offset + 1] & 0x3f) << 12
            c |= (bs[offset + 2] & 0x3f) << 6
            c |= bs[offset + 3] & 0x3f
            buf.push(chr(c))
            offset += 4
        else:
            # Invalid sequence. Move forward and try again.
            buf.push('\ufffd')
            offset += 1
    return ["".join([for ch in (buf) ch.asString()]), bs.slice(offset)]

def testDecodeCoreThreeBytes(assert):
    assert.equal(decodeCore(b`$\xe2`, null), ["", b`$\xe2`])
    assert.equal(decodeCore(b`$\xe2$\x8c`, null), ["", b`$\xe2$\x8c`])
    assert.equal(decodeCore(b`$\xe2$\x8c$\xb5`, null), ["⌵", b``])

unittest([testDecodeCoreThreeBytes])


def encodeCore(c :Char) :Bytes as DeepFrozen:
    def i := c.asInteger()
    def l := if (i < 0x80) {
        # One byte.
        [i]
    } else if (i < 0x800) {
        # Two bytes.
        [0xc0 | (i >> 6), 0x80 | (i & 0x3f)]
    } else if (i < 0x10000) {
        # Three bytes.
        [0xe0 | (i >> 12), 0x80 | ((i >> 6) & 0x3f), 0x80 | (i & 0x3f)]
    } else {
        # Four bytes.
        [
            0xf0 | (i >> 18),
            0x80 | ((i >> 12) & 0x3f),
            0x80 | ((i >> 6) & 0x3f),
            0x80 | (i & 0x3f),
        ]
    }
    return _makeBytes.fromInts(l)


# The codec itself.

object UTF8 as DeepFrozen:
    to decode(specimen, ej) :Str:
        def bs :Bytes exit ej := specimen
        def [s, remainder] exit ej := decodeCore(bs, ej)
        if (remainder.size() != 0):
            throw.eject(ej, [remainder, "was not empty"])
        return s

    to decodeExtras(specimen, ej):
        def bs :Bytes exit ej := specimen
        return decodeCore(bs, ej)

    to encode(specimen, ej) :Bytes:
        def s :Str exit ej := specimen
        var rv :Bytes := b``
        for c in (s):
            rv += encodeCore(c)
        return rv

def encodeBench():
    def via (UTF8.encode) xs := "This is a test of the UTF-8 encoder… "
    def via (UTF8.encode) ys := "¥ · £ · € · $ · ¢ · ₡ · ₢ · ₣ · ₤ · ₥ · ₦ · ₧ · ₨ · ₩ · ₪ · ₫ · ₭ · ₮ · ₯ · ₹"
    return xs + ys

bench(encodeBench, "UTF-8 encoding")


# def decodeBench():
#     def via (UTF8.decode) xs := b`This is a test of the UTF-8 encoder$\xe2$\x80$\xa6 `
#     def via (UTF8.decode) ys := _makeBytes.fromInts([194, 165, 32, 194, 183,
#                                                      32, 194, 163, 32, 194,
#                                                      183, 32, 226, 130, 172,
#                                                      32, 194, 183, 32, 36, 32,
#                                                      194, 183, 32, 194, 162,
#                                                      32, 194, 183, 32, 226,
#                                                      130, 161, 32, 194, 183,
#                                                      32, 226, 130, 162, 32,
#                                                      194, 183, 32, 226, 130,
#                                                      163, 32, 194, 183, 32,
#                                                      226, 130, 164, 32, 194,
#                                                      183, 32, 226, 130, 165,
#                                                      32, 194, 183, 32, 226,
#                                                      130, 166, 32, 194, 183,
#                                                      32, 226, 130, 167, 32,
#                                                      194, 183, 32, 226, 130,
#                                                      168, 32, 194, 183, 32,
#                                                      226, 130, 169, 32, 194,
#                                                      183, 32, 226, 130, 170,
#                                                      32, 194, 183, 32, 226,
#                                                      130, 171, 32, 194, 183,
#                                                      32, 226, 130, 173, 32,
#                                                      194, 183, 32, 226, 130,
#                                                      174, 32, 194, 183, 32,
#                                                      226, 130, 175, 32, 194,
#                                                      183, 32, 226, 130, 185])
#     return xs + ys

# bench(decodeBench, "UTF-8 decoding")
