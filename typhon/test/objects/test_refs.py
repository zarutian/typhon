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

from unittest import TestCase

from typhon.objects.collections import (ConstList, ConstMap, unwrapList,
                                        unwrapMap)
from typhon.objects.constants import unwrapBool, wrapBool
from typhon.objects.data import (DoubleObject, IntObject, promoteToDouble,
                                 unwrapInt)
from typhon.objects.refs import isResolved, makePromise, resolution


def makeNear(o):
    p, r = makePromise()
    r.resolve(o)
    return p


class TestIsResolved(TestCase):

    def testNearIsResolved(self):
        self.assertTrue(isResolved(IntObject(42)))

    def testSwitchableBecomesResolved(self):
        p, r = makePromise()
        self.assertFalse(isResolved(p))

        r.resolve(IntObject(42))
        self.assertTrue(isResolved(p))

    def testSwitchableChains(self):
        p, r = makePromise()
        p2, r2 = makePromise()

        r.resolve(p2)
        self.assertFalse(isResolved(p))

        r2.resolve(IntObject(42))
        self.assertTrue(isResolved(p))


class TestRefs(TestCase):

    def testResolveNear(self):
        p = makeNear(wrapBool(False))
        self.assertFalse(resolution(p).isTrue())


class TestUnwrappers(TestCase):

    def testPromoteToDoublePromise(self):
        p = makeNear(DoubleObject(4.2))
        self.assertAlmostEqual(promoteToDouble(p), 4.2)

    def testUnwrapBoolPromise(self):
        p = makeNear(wrapBool(False))
        self.assertFalse(unwrapBool(p))

    def testUnwrapIntPromise(self):
        p = makeNear(IntObject(42))
        self.assertEqual(unwrapInt(p), 42)

    def testUnwrapListPromise(self):
        p = makeNear(ConstList.fromList([]))
        self.assertEqual(unwrapList(p), [])

    def testUnwrapMapPromise(self):
        p = makeNear(ConstMap({}))
        self.assertEqual(unwrapMap(p).items(), [])
