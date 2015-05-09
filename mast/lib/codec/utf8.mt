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

def [=> Bytes] | _ := import("lib/bytes")


def chr(i :Int) :Char:
    return '\x00' + i

def testChr(assert):
    assert.equal('\x00', chr(0x00))
    assert.equal('\n', chr(0x0a))
    # XXX assert.equal('▲', chr(0x25b2))
    assert.equal('\u25b2', chr(0x25b2))

unittest([testChr])


def decodeCore(var bs :Bytes, ej):
    def iterator := bs._makeIterator()
    var rv :Str := ""
    while (true):
        switch (bs):
            match [b ? ((b & 0x80) == 0x00)] + rest:
                # One byte.
                rv with= chr(b)
                bs := rest
            match [b ? ((b & 0xe0) == 0xc0), x] + rest:
                # Two bytes.
                var c := (b & 0x1f) << 6
                c |= x & 0x3f
                rv with= chr(c)
                bs := rest
            match [b ? ((b & 0xf0) == 0xe0), x, y] + rest:
                # Three bytes.
                var c := (b & 0x0f) << 12
                c |= (x & 0x3f) << 6
                c |= y & 0x3f
                rv with= chr(c)
                bs := rest
            match [b ? ((b & 0xf7) == 0xf0), x, y, z] + rest:
                # Four bytes.
                var c := (b & 0x07) << 18
                c |= (x & 0x3f) << 12
                c |= (y & 0x3f) << 6
                c |= z & 0x3f
                rv with= chr(c)
                bs := rest
            match _:
                break
    return [rv, bs]

def testDecodeCore(assert):
    # One byte.
    assert.equal(["\x00", []], decodeCore([0x00], null))
    assert.equal(["\n", []], decodeCore([0x0a], null))
    # One byte as leftover.
    assert.equal(["", [0xc3]], decodeCore([0xc3], null))
    # Two bytes.
    # XXX é
    assert.equal(["\u00e9", []], decodeCore([0xc3, 0xa9], null))
    # Three bytes.
    # XXX ▲
    assert.equal(["\u25b2", []], decodeCore([0xe2, 0x96, 0xb2], null))
    # Four bytes.
    # XXX this codepoint is generally not in any font
    assert.equal(["\U0001f3d4", []],
                 decodeCore([0xf0, 0x9f, 0x8f, 0x94], null))

unittest([testDecodeCore])


def encodeCore(c :Char) :Bytes:
    return switch (c.asInteger()) {
        # One byte.
        match i ? (i < 0x80) {[i]}
        # Two bytes.
        match i ? (i < 0x800) {[0xc0 | (i >> 6), 0x80 | (i & 0x3f)]}
        # Three bytes.
        match i ? (i < 0x10000) {
            [0xe0 | (i >> 12), 0x80 | ((i >> 6) & 0x3f), 0x80 | (i & 0x3f)]
        }
        # Four bytes.
        match i {
            [
                0xf0 | (i >> 18),
                0x80 | ((i >> 12) & 0x3f),
                0x80 | ((i >> 6) & 0x3f),
                0x80 | (i & 0x3f),
            ]
        }
    }

def testEncodeCore(assert):
    # One byte.
    assert.equal([0x00], encodeCore('\x00'))
    # Two bytes.
    # XXX é
    assert.equal([0xc3, 0xa9], encodeCore('\u00e9'))
    # Three bytes.
    # XXX ▲
    assert.equal([0xe2, 0x96, 0xb2], encodeCore('\u25b2'))
    # Four bytes.
    # XXX this codepoint is generally not in any font
    assert.equal([0xf0, 0x9f, 0x8f, 0x94], encodeCore('\U0001f3d4'))

unittest([testEncodeCore])


# The codec itself.

object UTF8:
    to decode(specimen, ej) :Str:
        def bs :Bytes exit ej := specimen
        # XXX def [s, []] exit ej := decodeCore(bs, ej)
        def [s, ==[]] exit ej := decodeCore(bs, ej)
        return s

    to decodeExtras(specimen, ej):
        def bs :Bytes exit ej := specimen
        return decodeCore(bs, ej)

    to encode(specimen, ej) :Bytes:
        def s :Str exit ej := specimen
        var rv := []
        for c in s:
            rv += encodeCore(c)
        return rv

def testUTF8Decode(assert):
    assert.ejects(fn ej {def via (UTF8.decode) x exit ej := [0xc3]})
    assert.doesNotEject(fn ej {def via (UTF8.decode) x exit ej := [0xc3, 0xa9]})

def testUTF8Encode(assert):
    assert.ejects(fn ej {def via (UTF8.encode) x exit ej := 42})
    assert.doesNotEject(fn ej {def via (UTF8.encode) x exit ej := "yes"})

unittest([
    testUTF8Decode,
    testUTF8Encode,
])


[
    => UTF8,
]