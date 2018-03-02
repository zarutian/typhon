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

from rpython.rlib.jit import elidable

from typhon.autohelp import autohelp, method
from typhon.errors import Ejecting, userError
from typhon.errors import UserException
from typhon.objects.collections.helpers import MonteSorter
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.ejectors import Ejector, throwStr
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon
from typhon.rstrategies import rstrategies
from typhon.strategies.lists import strategyFactory


@autohelp
class listIterator(Object):
    """
    An iterator on a list, producing its elements.
    """

    _immutable_fields_ = "objects[*]", "size"

    _index = 0

    def __init__(self, objects):
        self.objects = objects
        self.size = len(objects)

    def toString(self):
        return u"<listIterator>"

    @method("List", "Any")
    def next(self, ej):
        """
        Takes an ejector and returns the next [index, value] from the iterator or if throws "Iterator exhausted".
        """
        if self._index < self.size:
            rv = [IntObject(self._index), self.objects[self._index]]
            self._index += 1
            return rv
        else:
            throwStr(ej, u"Iterator exhausted")


@autohelp
class FlexList(Object):
    """
    A mutable list of objects.
    """

    rstrategies.make_accessors(strategy="strategy", storage="storage")

    strategy = None

    def __init__(self, flexObjects):
        strategy = strategyFactory.strategy_type_for(flexObjects)
        strategyFactory.set_initial_strategy(self, strategy, len(flexObjects),
                                             flexObjects)

    def toString(self):
        return toString(self)

    @method("Void", "Any")
    def _printOn(self, printer):
        """
        Given a printer, the object prints a human readable representation of itself on it.
        """
        printer.call(u"print", [StrObject(u"[")])
        items = self.strategy.fetch_all(self)
        for i, obj in enumerate(items):
            printer.call(u"quote", [obj])
            if i + 1 < len(items):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].diverge()")])

    @method("Bool")
    def empty(self):
        """
        deprecated, use isEmpty/0 instead.
        Returns true if the list is empty returns false otherwise.
        """
        return self.strategy.size(self) == 0

    @method("List", "List")
    def join(self, pieces):
        """
        Joins an list on the end of this list together into a new one.
        """
        l = []
        filler = self.strategy.fetch_all(self)
        first = True
        for piece in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                l.extend(filler)

            l.append(piece)
        return l[:]

    @method("List")
    def _uncall(self):
        """
        Returns a Portrayal of itself which is used for serialization and some comparison purposes.
        """
        from typhon.objects.collections.maps import EMPTY_MAP
        return [wrapList(self.snapshot()), StrObject(u"diverge"),
                wrapList([]), EMPTY_MAP]

    @method("List", "List")
    def add(self, other):
        """
        Joins a lists onto this list as a new one and returns it.
        """
        return self.strategy.fetch_all(self) + other

    @method("Any")
    def diverge(self):
        """
        Makes a mutable copy of the list. (FlexList)
        """
        return FlexList(self.strategy.fetch_all(self))

    @method("Void", "Any")
    def extend(self, other):
        """
        Appends the item to the list.
        """
        # XXX factor me plz
        try:
            data = unwrapList(other)
        except:
            data = listFromIterable(other)
        # Required to avoid passing an empty list to .append(), which
        # apparently cannot deal. Also a quick win. ~ C.
        if len(data) != 0:
            self.strategy.append(self, data)

    @method("Any", "Int")
    def get(self, index):
        """
        Lookup by index (a postitive integer) into the list.
        """
        # Lookup by index.
        if index >= self.strategy.size(self) or index < 0:
            raise userError(u"get/1: Index %d is out of bounds" % index)
        return self.strategy.fetch(self, index)

    @method("Void", "Int", "Any")
    def insert(self, index, value):
        """
        Inserts the item at index position (a postive integer) given in the list.
        """
        if index < 0:
            raise userError(u"insert/2: Index %d is out of bounds" % index)
        self.strategy.insert(self, index, [value])

    @method("Any")
    def last(self):
        """
        Returns the last item of the list.
        """
        size = self.strategy.size(self)
        if size:
            return self.strategy.fetch(self, size - 1)
        raise userError(u"last/0: Empty list has no last element")

    @method("List", "Int")
    def multiply(self, count):
        """
        Create a new list by repeating the contents of this list, count (postive integer) times.
        """
        # multiply/1: Create a new list by repeating this list's contents.
        return self.strategy.fetch_all(self) * count

    @method("Any")
    def pop(self):
        """
        Pops the last item off the list and returns it.
        """
        try:
            return self.strategy.pop(self, self.strategy.size(self) - 1)
        except IndexError:
            raise userError(u"pop/0: Pop from empty list")

    @method("Void", "Any")
    def push(self, value):
        """
        Pushes the item given onto the end of the list.
        """
        self.strategy.append(self, [value])

    @method("List")
    def reverse(self):
        """
        Returns a reversed list copy of this list.
        """
        new = self.strategy.fetch_all(self)[:]
        new.reverse()
        return new

    @method("Void")
    def reverseInPlace(self):
        """
        Rerverses the list in place.
        """
        new = self.strategy.fetch_all(self)[:]
        new.reverse()
        self.strategy.store_all(self, new)

    @method("List", "Any", _verb="with")
    def _with(self, value):
        """
        Create a new list with the appended item added.
        """
        # with/1: Create a new list with an appended object.
        return self.strategy.fetch_all(self) + [value]

    @method("List", "Int", "Any", _verb="with")
    def withIndex(self, index, value):
        """
        Makes a new ConstList where the index'th (postive integer) item has been replaced with the given value.
        """
        # Make a new ConstList.
        if index >= self.strategy.size(self) or index < 0:
            raise userError(u"with/2: Index %d is out of bounds" % index)
        new = self.strategy.fetch_all(self)[:]
        new[index] = value
        return new

    @method("Any")
    def _makeIterator(self):
        """
        Makes a new iterator that iterates over a snopshot of the list made when the iterator was made.
        """
        # This is the behavior we choose: Iterating over a FlexList grants
        # iteration over a snapshot of the list's contents at that point.
        return listIterator(self.strategy.fetch_all(self))

    @method("Map")
    def asMap(self):
        """
        Makes an map out of the list. (Incomplete docu)
        """
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self.strategy.fetch_all(self)):
            d[IntObject(i)] = o
        return d

    @method("Set")
    def asSet(self):
        """
        Makes an set out of the list. (Incomplete docu)
        """
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for o in self.strategy.fetch_all(self):
            d[o] = None
        return d

    @method.py("Bool", "Any")
    def contains(self, needle):
        """
        Checks if the given value is in the list or not.
        """
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.strategy.fetch_all(self):
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    @method("Int", "Any")
    def indexOf(self, needle):
        """
        Returns the index of the given value if found. Returns -1 otherwise.
        """
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self.strategy.fetch_all(self)):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    @method.py("Void", "Int", "Any")
    def put(self, index, value):
        """
        Sets the index'th place of the list to the given value.
        """
        top = self.strategy.size(self)
        if 0 <= index < top:
            self.strategy.store(self, index, value)
        else:
            raise userError(u"put/2: Index %d out of bounds for list of length %d" %
                           (index, top))

    @method("Int")
    def size(self):
        """
        Returns the number of items in the list.
        """
        return self.strategy.size(self)

    @method("Bool")
    def isEmpty(self):
        """
        Returns true if the list is empty, false otherwise.
        """
        return not self.strategy.size(self)

    @method("List", "Int")
    def slice(self, start):
        """
        Returns the second half of the list after the given slice index.
        """
        if start < 0:
            raise userError(u"slice/1: Negative start")
        stop = self.strategy.size(self)
        return self.strategy.slice(self, start, stop)

    @method("List", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        """
        Returns the slice of the list that starts at first given index upto the second given index.
        """
        if start < 0:
            raise userError(u"slice/2: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        return self.strategy.slice(self, start, stop)

    @method.py("List")
    def snapshot(self):
        """
        Returns an ConstList snapshot of the list. (The snapshot is immutable.)
        """
        return self.strategy.fetch_all(self)


def unwrapList(o, ej=None):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l.objs
    if isinstance(l, FlexList):
        return l.strategy.fetch_all(l)
    throwStr(ej, u"Not a list!")

def isList(obj):
    from typhon.objects.refs import resolution
    o = resolution(obj)
    return isinstance(o, ConstList) or isinstance(o, FlexList)


def listFromIterable(obj):
    rv = []
    iterator = obj.call(u"_makeIterator", [])
    with Ejector() as ej:
        while True:
            try:
                l = unwrapList(iterator.call(u"next", [ej]))
                if len(l) != 2:
                    raise userError(u"makeList.fromIterable/1: Invalid iterator")
                rv.append(l[1])
            except Ejecting as ex:
                if ex.ejector is ej:
                    return rv[:]
                raise


@autohelp
@audited.Transparent
class ConstList(Object):
    """
    An immutable list of objects.
    """

    _immutable_fields_ = "objs[*]",

    _isSettled = False

    def __init__(self, objs):
        self.objs = objs

    # Do some voodoo for pretty-printing. Cargo-culted voodoo. ~ C.

    def toQuote(self):
        return toString(self)

    def toString(self):
        return toString(self)

    @method("Void", "Any")
    def _printOn(self, printer):
        """
        Given a printer, the object prints a human readable representation of itself on it.
        """
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objs):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objs):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"]")])

    def computeHash(self, depth):
        """
        Computes an non-cryptographic hashmap hash.
        """
        from typhon.objects.equality import samenessHash
        return samenessHash(self, depth, None)

    def isSettled(self, sofar=None):
        """
        Returns true if the list elements are settled, false otherwise.
        """
        # Check for a usable cached result.
        if self._isSettled:
            return True

        # No cache; do this the hard way.
        if sofar is None:
            sofar = {self: None}
        for v in self.objs:
            if v not in sofar and not v.isSettled(sofar=sofar):
                return False

        # Cache this success; we can't become unsettled.
        self._isSettled = True
        return True

    @method("Bool")
    def empty(self):
        """
        deprecated, use isEmpty/0 instead.
        Returns true if the list is empty returns false otherwise.
        """
        return bool(self.objs)

    @method("List", "List")
    @profileTyphon("List.add/1")
    def add(self, other):
        """
        Joins a lists onto this list as a new one and returns it.
        """
        if other:
            return self.objs + other
        else:
            return self.objs

    @method("List", "List")
    @profileTyphon("List.join/1")
    def join(self, pieces):
        """
        Joins an list on the end of this list together into a new one.
        """
        l = []
        filler = self.objs
        first = True
        for piece in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                l.extend(filler)

            l.append(piece)
        return l[:]

    @method("Any")
    def diverge(self):
        """
        Makes a mutable copy of the list. (FlexList)
        """
        # XXX is this copy necessary?
        return FlexList(self.objs[:])

    @method("Any", "Int")
    def get(self, index):
        """
        Lookup by index (a postitive integer) into the list.
        """
        # Lookup by index.
        if index < 0:
            raise userError(u"get/1: Index %d cannot be negative" % index)

        try:
            return self.objs[index]
        except IndexError:
            raise userError(u"get/1: Index %d is out of bounds" % index)

    @method("Any")
    def last(self):
        """
        Returns the last item of the list.
        """
        if self.objs:
            return self.objs[-1]
        else:
            raise userError(u"last/0: Empty list has no last element")

    @method("List", "Int")
    def multiply(self, count):
        """
        Create a new list by repeating the contents of this list, count (postive integer) times.
        """
        # multiply/1: Create a new list by repeating this list's contents.
        if count < 0:
            raise userError(u"multiply/1: Can't multiply list %d times" % count)
        elif count == 0:
            return []
        else:
            return self.objs * count

    @method("List")
    def reverse(self):
        """
        Returns a reversed list copy of this list.
        """
        l = self.objs[:]
        l.reverse()
        return l

    @method("List", "Int", "Any", _verb="with")
    def _with(self, index, value):
        """
        Create a new list with the appended item added.
        """
        # Replace by index.
        return self.put(index, value)

    @method("List")
    def _uncall(self):
        """
        Returns a Portrayal of itself which is used for serialization and some comparison purposes.
        """
        from typhon.scopes.safe import theMakeList
        from typhon.objects.collections.maps import EMPTY_MAP
        return [theMakeList, StrObject(u"run"), self, EMPTY_MAP]

    @method("Any")
    def _makeIterator(self):
        """
        Makes a new iterator that iterates over a snopshot of the list made when the iterator was made.
        """
        # XXX could be more efficient with case analysis
        return listIterator(self.objs)

    @method("Map")
    def asMap(self):
        """
        Makes an map out of the list. (Incomplete docu)
        """
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self.objs):
            d[IntObject(i)] = o
        return d

    @method("Set")
    def asSet(self):
        """
        Makes an set out of the list. (Incomplete docu)
        """
        from typhon.objects.collections.sets import monteSet
        d = monteSet()
        for o in self.objs:
            d[o] = None
        return d

    @method("Int", "List")
    @profileTyphon("List.op__cmp/1")
    def op__cmp(self, other):
        for i, left in enumerate(self.objs):
            try:
                right = other[i]
            except IndexError:
                # They're shorter than us.
                return 1
            try:
                result = unwrapInt(left.call(u"op__cmp", [right]))
            except UserException:
                result = -unwrapInt(right.call(u"op__cmp", [left]))
            if result < 0:
                return -1
            if result > 0:
                return 1
        # They could be longer than us but we were equal up to this point.
        # Do a final length check.
        return 0 if len(self.objs) == len(other) else -1

    @method("Bool", "Any")
    @profileTyphon("List.contains/1")
    def contains(self, needle):
        """
        Checks if the given value is in the list or not.
        """
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.objs:
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    @method("Int", "Any")
    @profileTyphon("List.indexOf/1")
    def indexOf(self, needle):
        """
        Returns the index of the given value if found. Returns -1 otherwise.
        """
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self.objs):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    @method.py("List", "Any", _verb="with")
    @profileTyphon("List.with/1")
    def with_(self, obj):
        """
        Create a new list with the appended item added.
        """
        if not self.objs:
            return [obj]
        else:
            return self.objs + [obj]

    @method.py("List", "Int", "Any")
    def put(self, index, value):
        """
        Makes a new list where index'th item has been replaced with the given value.
        """
        top = len(self.objs)
        if index == top:
            return self.with_(value)
        else:
            try:
                objs = self.objs[:]
                objs[index] = value
                return objs
            except IndexError:
                raise userError(u"put/2: Index %d out of bounds for list of length %d" %
                                (index, top))

    @method.py("Int")
    @elidable
    def size(self):
        """
        Returns the number of items in the list.
        """
        return len(self.objs)

    @method("Bool")
    def isEmpty(self):
        """
        Returns true if the list is empty returns false otherwise.
        """
        return not self.objs

    @method("List", "Int")
    def slice(self, start):
        """
        Returns the second half of the list after the given slice index.
        """
        if start < 0:
            raise userError(u"slice/1: Negative start")
        stop = len(self.objs)
        start = min(start, stop)
        return self.objs[start:stop]

    @method("List", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        """
        Returns the slice of the list that starts at first given index upto the second given index.
        """
        if start < 0:
            raise userError(u"slice/1: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        stop = min(stop, len(self.objs))
        start = min(start, stop)
        return self.objs[start:stop]

    @method("Any")
    def snapshot(self):
        """
        Returns the list itself as it is already immutable.
        """
        return self

    @method("List")
    @profileTyphon("List.sort/0")
    def sort(self):
        """
        Returns a sorted copy of the list.
        """
        l = self.objs[:]
        MonteSorter(l).sort()
        return l

    @method("Int", "List")
    def startOf(self, needleCL, start=0):
        """
        Returns the starting index of where the given sublist starts in the list. Returns -1 otherwise.
        """
        return self._startOf(needleCL, 0)

    @method.py("Int", "List", "Int", _verb="startOf")
    def _startOf(self, needleCL, start):
        """
        Returns the starting index of where the given sublist starts in the list. Returns -1 otherwise.
        """
        if start < 0:
            raise userError(u"startOf/2: Negative start %d not permitted" %
                    start)
        # This is quadratic. It could be better.
        from typhon.objects.equality import EQUAL, optSame
        for index in range(start, len(self.objs)):
            for needleIndex, needle in enumerate(needleCL):
                offset = index + needleIndex
                if optSame(self.objs[offset], needle) is not EQUAL:
                    break
                return index
        return -1


def wrapList(l):
    return ConstList(l)
