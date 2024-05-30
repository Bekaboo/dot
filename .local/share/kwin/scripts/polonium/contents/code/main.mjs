var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __commonJS = (cb, mod) => function __require() {
  return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));

// node_modules/obliterator/support.js
var require_support = __commonJS({
  "node_modules/obliterator/support.js"(exports) {
    exports.ARRAY_BUFFER_SUPPORT = typeof ArrayBuffer !== "undefined";
    exports.SYMBOL_SUPPORT = typeof Symbol !== "undefined";
  }
});

// node_modules/obliterator/foreach.js
var require_foreach = __commonJS({
  "node_modules/obliterator/foreach.js"(exports, module) {
    var support = require_support();
    var ARRAY_BUFFER_SUPPORT = support.ARRAY_BUFFER_SUPPORT;
    var SYMBOL_SUPPORT = support.SYMBOL_SUPPORT;
    module.exports = function forEach(iterable, callback) {
      var iterator, k, i, l, s;
      if (!iterable)
        throw new Error("obliterator/forEach: invalid iterable.");
      if (typeof callback !== "function")
        throw new Error("obliterator/forEach: expecting a callback.");
      if (Array.isArray(iterable) || ARRAY_BUFFER_SUPPORT && ArrayBuffer.isView(iterable) || typeof iterable === "string" || iterable.toString() === "[object Arguments]") {
        for (i = 0, l = iterable.length; i < l; i++)
          callback(iterable[i], i);
        return;
      }
      if (typeof iterable.forEach === "function") {
        iterable.forEach(callback);
        return;
      }
      if (SYMBOL_SUPPORT && Symbol.iterator in iterable && typeof iterable.next !== "function") {
        iterable = iterable[Symbol.iterator]();
      }
      if (typeof iterable.next === "function") {
        iterator = iterable;
        i = 0;
        while (s = iterator.next(), s.done !== true) {
          callback(s.value, i);
          i++;
        }
        return;
      }
      for (k in iterable) {
        if (iterable.hasOwnProperty(k)) {
          callback(iterable[k], k);
        }
      }
      return;
    };
  }
});

// node_modules/mnemonist/bi-map.js
var require_bi_map = __commonJS({
  "node_modules/mnemonist/bi-map.js"(exports, module) {
    var forEach = require_foreach();
    function InverseMap(original) {
      this.size = 0;
      this.items = /* @__PURE__ */ new Map();
      this.inverse = original;
    }
    function BiMap3() {
      this.size = 0;
      this.items = /* @__PURE__ */ new Map();
      this.inverse = new InverseMap(this);
    }
    function clear() {
      this.size = 0;
      this.items.clear();
      this.inverse.items.clear();
    }
    BiMap3.prototype.clear = clear;
    InverseMap.prototype.clear = clear;
    function set(key, value) {
      if (this.items.has(key)) {
        var currentValue = this.items.get(key);
        if (currentValue === value)
          return this;
        else
          this.inverse.items.delete(currentValue);
      }
      if (this.inverse.items.has(value)) {
        var currentKey = this.inverse.items.get(value);
        if (currentKey === key)
          return this;
        else
          this.items.delete(currentKey);
      }
      this.items.set(key, value);
      this.inverse.items.set(value, key);
      this.size = this.items.size;
      this.inverse.size = this.inverse.items.size;
      return this;
    }
    BiMap3.prototype.set = set;
    InverseMap.prototype.set = set;
    function del(key) {
      if (this.items.has(key)) {
        var currentValue = this.items.get(key);
        this.items.delete(key);
        this.inverse.items.delete(currentValue);
        this.size = this.items.size;
        this.inverse.size = this.inverse.items.size;
        return true;
      }
      return false;
    }
    BiMap3.prototype.delete = del;
    InverseMap.prototype.delete = del;
    var METHODS = ["has", "get", "forEach", "keys", "values", "entries"];
    METHODS.forEach(function(name) {
      BiMap3.prototype[name] = InverseMap.prototype[name] = function() {
        return Map.prototype[name].apply(this.items, arguments);
      };
    });
    if (typeof Symbol !== "undefined") {
      BiMap3.prototype[Symbol.iterator] = BiMap3.prototype.entries;
      InverseMap.prototype[Symbol.iterator] = InverseMap.prototype.entries;
    }
    BiMap3.prototype.inspect = function() {
      var dummy = {
        left: this.items,
        right: this.inverse.items
      };
      Object.defineProperty(dummy, "constructor", {
        value: BiMap3,
        enumerable: false
      });
      return dummy;
    };
    if (typeof Symbol !== "undefined")
      BiMap3.prototype[Symbol.for("nodejs.util.inspect.custom")] = BiMap3.prototype.inspect;
    InverseMap.prototype.inspect = function() {
      var dummy = {
        left: this.inverse.items,
        right: this.items
      };
      Object.defineProperty(dummy, "constructor", {
        value: InverseMap,
        enumerable: false
      });
      return dummy;
    };
    if (typeof Symbol !== "undefined")
      InverseMap.prototype[Symbol.for("nodejs.util.inspect.custom")] = InverseMap.prototype.inspect;
    BiMap3.from = function(iterable) {
      var bimap = new BiMap3();
      forEach(iterable, function(value, key) {
        bimap.set(key, value);
      });
      return bimap;
    };
    module.exports = BiMap3;
  }
});

// node_modules/obliterator/iterator.js
var require_iterator = __commonJS({
  "node_modules/obliterator/iterator.js"(exports, module) {
    function Iterator(next) {
      if (typeof next !== "function")
        throw new Error("obliterator/iterator: expecting a function!");
      this.next = next;
    }
    if (typeof Symbol !== "undefined")
      Iterator.prototype[Symbol.iterator] = function() {
        return this;
      };
    Iterator.of = function() {
      var args = arguments, l = args.length, i = 0;
      return new Iterator(function() {
        if (i >= l)
          return { done: true };
        return { done: false, value: args[i++] };
      });
    };
    Iterator.empty = function() {
      var iterator = new Iterator(function() {
        return { done: true };
      });
      return iterator;
    };
    Iterator.fromSequence = function(sequence) {
      var i = 0, l = sequence.length;
      return new Iterator(function() {
        if (i >= l)
          return { done: true };
        return { done: false, value: sequence[i++] };
      });
    };
    Iterator.is = function(value) {
      if (value instanceof Iterator)
        return true;
      return typeof value === "object" && value !== null && typeof value.next === "function";
    };
    module.exports = Iterator;
  }
});

// node_modules/mnemonist/queue.js
var require_queue = __commonJS({
  "node_modules/mnemonist/queue.js"(exports, module) {
    var Iterator = require_iterator();
    var forEach = require_foreach();
    function Queue4() {
      this.clear();
    }
    Queue4.prototype.clear = function() {
      this.items = [];
      this.offset = 0;
      this.size = 0;
    };
    Queue4.prototype.enqueue = function(item) {
      this.items.push(item);
      return ++this.size;
    };
    Queue4.prototype.dequeue = function() {
      if (!this.size)
        return;
      var item = this.items[this.offset];
      if (++this.offset * 2 >= this.items.length) {
        this.items = this.items.slice(this.offset);
        this.offset = 0;
      }
      this.size--;
      return item;
    };
    Queue4.prototype.peek = function() {
      if (!this.size)
        return;
      return this.items[this.offset];
    };
    Queue4.prototype.forEach = function(callback, scope) {
      scope = arguments.length > 1 ? scope : this;
      for (var i = this.offset, j = 0, l = this.items.length; i < l; i++, j++)
        callback.call(scope, this.items[i], j, this);
    };
    Queue4.prototype.toArray = function() {
      return this.items.slice(this.offset);
    };
    Queue4.prototype.values = function() {
      var items = this.items, i = this.offset;
      return new Iterator(function() {
        if (i >= items.length)
          return {
            done: true
          };
        var value = items[i];
        i++;
        return {
          value,
          done: false
        };
      });
    };
    Queue4.prototype.entries = function() {
      var items = this.items, i = this.offset, j = 0;
      return new Iterator(function() {
        if (i >= items.length)
          return {
            done: true
          };
        var value = items[i];
        i++;
        return {
          value: [j++, value],
          done: false
        };
      });
    };
    if (typeof Symbol !== "undefined")
      Queue4.prototype[Symbol.iterator] = Queue4.prototype.values;
    Queue4.prototype.toString = function() {
      return this.toArray().join(",");
    };
    Queue4.prototype.toJSON = function() {
      return this.toArray();
    };
    Queue4.prototype.inspect = function() {
      var array = this.toArray();
      Object.defineProperty(array, "constructor", {
        value: Queue4,
        enumerable: false
      });
      return array;
    };
    if (typeof Symbol !== "undefined")
      Queue4.prototype[Symbol.for("nodejs.util.inspect.custom")] = Queue4.prototype.inspect;
    Queue4.from = function(iterable) {
      var queue = new Queue4();
      forEach(iterable, function(value) {
        queue.enqueue(value);
      });
      return queue;
    };
    Queue4.of = function() {
      return Queue4.from(arguments);
    };
    module.exports = Queue4;
  }
});

// src/util/log.ts
var Log = class {
  constructor(config, root) {
    this.printFn = root.printQml;
    this.debugEnabled = config.debug;
  }
  print(opener, stuff) {
    if (this.printFn == void 0) {
      return;
    }
    let ret = opener;
    for (const s of stuff) {
      ret += " ";
      if (s === null) {
        ret += "null";
      } else if (s === void 0) {
        ret += "undefined";
      } else if (typeof s == "string") {
        ret += s;
      } else {
        ret += s.toString();
      }
    }
    this.printFn(ret);
  }
  debug(...stuff) {
    if (!this.debugEnabled)
      return;
    this.print("Polonium DBG:", stuff);
  }
  info(...stuff) {
    this.print("Polonium INF:", stuff);
  }
  error(...stuff) {
    this.print("Polonium ERR:", stuff);
  }
};

// src/util/geometry.ts
var DirectionTools = class {
  constructor(d) {
    this.d = d;
  }
  // rotate clockwise 90 deg
  rotateCw() {
    let ret = (this.d & 4 /* Vertical */) == 4 /* Vertical */ ? 0 /* None */ : 4 /* Vertical */;
    if ((this.d & 1 /* Up */) == 1 /* Up */) {
      if ((this.d & 2 /* Right */) == 2 /* Right */) {
        ret |= 2 /* Right */;
      } else {
        ret |= 2 /* Right */ | 1 /* Up */;
      }
    } else {
      if ((this.d & 2 /* Right */) == 2 /* Right */) {
        ret |= 0 /* None */;
      } else {
        ret |= 1 /* Up */;
      }
    }
    return ret;
  }
  // rotate counterclockwise 90 deg
  rotateCcw() {
    let ret = (this.d & 4 /* Vertical */) == 4 /* Vertical */ ? 0 /* None */ : 4 /* Vertical */;
    if ((this.d & 1 /* Up */) == 1 /* Up */) {
      if ((this.d & 2 /* Right */) == 2 /* Right */) {
        ret |= 1 /* Up */;
      } else {
        ret |= 0 /* None */;
      }
    } else {
      if ((this.d & 2 /* Right */) == 2 /* Right */) {
        ret |= 1 /* Up */ | 2 /* Right */;
      } else {
        ret |= 2 /* Right */;
      }
    }
    return ret;
  }
};
var GPoint = class _GPoint {
  constructor(p) {
    this.x = 0;
    this.y = 0;
    if (p == void 0) {
      return;
    }
    this.x = p.x;
    this.y = p.y;
  }
  static centerOfRect(r) {
    return new _GPoint({
      x: r.x + r.width / 2,
      y: r.y + r.height / 2
    });
  }
  toString() {
    return "GPoint(" + this.x + ", " + this.y + ")";
  }
};
var GRect = class {
  constructor(r) {
    this.x = 0;
    this.y = 0;
    this.width = 0;
    this.height = 0;
    if (r == void 0) {
      return;
    }
    this.x = r.x;
    this.y = r.y;
    this.width = r.width;
    this.height = r.height;
  }
  directionFromPoint(p) {
    const relativePoint = new GPoint({
      x: p.x - this.x,
      y: p.y - this.y
    });
    if (relativePoint.x < this.width / 2) {
      if (relativePoint.y < this.height / 2) {
        if (relativePoint.x > this.width * relativePoint.y / this.height) {
          return 1 /* Up */ | 4 /* Vertical */;
        } else {
          return 1 /* Up */;
        }
      } else {
        if (relativePoint.x > this.width * relativePoint.y / this.height) {
          return 4 /* Vertical */;
        } else {
          return 0 /* None */;
        }
      }
    } else {
      if (relativePoint.y < this.height / 2) {
        if (relativePoint.x < this.width * relativePoint.y / this.height) {
          return 2 /* Right */ | 1 /* Up */ | 4 /* Vertical */;
        } else {
          return 2 /* Right */ | 1 /* Up */;
        }
      } else {
        if (relativePoint.x < this.width * relativePoint.y / this.height) {
          return 2 /* Right */ | 4 /* Vertical */;
        } else {
          return 2 /* Right */;
        }
      }
    }
  }
  get center() {
    return new GPoint({
      x: this.x + this.width / 2,
      y: this.y + this.height / 2
    });
  }
  contains(rect) {
    if (rect.x < this.x || rect.y < this.y) {
      return false;
    }
    if (rect.x + rect.width > this.x + this.width || rect.y + rect.height > this.y + this.height) {
      return false;
    }
    return true;
  }
  toString() {
    return "GRect(" + this.x + ", " + this.y + +", " + this.width + ", " + this.height + ")";
  }
};
var GSize = class _GSize {
  constructor(s) {
    this.width = 0;
    this.height = 0;
    if (s == void 0) {
      return;
    }
    this.width = s.width;
    this.height = s.height;
  }
  static fromRect(r) {
    return new _GSize({
      width: r.width,
      height: r.height
    });
  }
  isEqual(s) {
    return s.width == this.width && s.height == this.height;
  }
  // compare two sizes and grow the caller if it is too small
  fitSize(s) {
    if (this.height < s.height) {
      this.height = s.height;
    }
    if (this.width < s.width) {
      this.width = s.width;
    }
  }
  write(s) {
    if (s.width != this.width) {
      s.width = this.width;
    }
    if (s.height != this.height) {
      s.height = this.height;
    }
  }
  get area() {
    return this.width * this.height;
  }
  toString() {
    return "GSize(" + this.width + ", " + this.height + ")";
  }
};

// src/engine/engine.ts
var Tile = class _Tile {
  constructor(parent, alterSiblingRatios = true) {
    this.tiles = [];
    this.layoutDirection = 1 /* Horizontal */;
    // requested size in pixels, may not be honored
    this.requestedSize = new GSize();
    // requested relative size to screen, more likely to be honored
    this.relativeSize = 1;
    this.clients = [];
    this.parent = parent ?? null;
    if (this.parent == null) {
      return;
    }
    this.parent.tiles.push(this);
    if (!alterSiblingRatios) {
      return;
    }
    const childrenLen = this.parent.tiles.length;
    if (childrenLen <= 1) {
      return;
    }
    this.relativeSize = 1 / (childrenLen - 1);
    for (const child of this.parent.tiles) {
      child.relativeSize *= (childrenLen - 1) / childrenLen;
    }
  }
  // getter/setter for backwards compatibility
  get client() {
    return this.clients.length > 0 ? this.clients[0] : null;
  }
  set client(value) {
    if (value != null) {
      this.clients[0] = value;
    } else {
      this.clients = [];
    }
  }
  // adds a child that will split perpendicularly to the parent. Returns the child
  addChild(alterSiblingRatios = true) {
    let splitDirection = 1;
    if (this.layoutDirection == 1) {
      splitDirection = 2;
    }
    const childTile = new _Tile(this, alterSiblingRatios);
    childTile.layoutDirection = splitDirection;
    return childTile;
  }
  // adds a child that will split parallel to the parent. Not really recommeneded
  addChildParallel(alterSiblingRatios = true) {
    const childTile = new _Tile(this, alterSiblingRatios);
    childTile.layoutDirection = this.layoutDirection;
    return childTile;
  }
  // split a tile perpendicularly
  split() {
    this.addChild();
    this.addChild();
  }
  // have a tile replace its parent, destroying its siblings
  secede() {
    const parent = this.parent;
    if (parent == null) {
      return;
    }
    this.parent = parent.parent;
    if (this.parent != null) {
      this.parent.tiles[this.parent.tiles.indexOf(parent)] = this;
      for (const tile of parent.tiles) {
        if (tile != this) {
          tile.remove(true);
        }
      }
      parent.tiles = [];
      parent.client = null;
    } else {
      parent.client = this.client;
      parent.tiles = this.tiles;
      this.tiles = [];
      this.client = null;
    }
  }
  // removes a tile and all its children
  remove(batchRemove = false) {
    const parent = this.parent;
    if (parent == null) {
      return;
    }
    if (!batchRemove) {
      parent.tiles.splice(parent.tiles.indexOf(this), 1);
    }
    const childrenLen = parent.tiles.length;
    for (const child of parent.tiles) {
      child.relativeSize *= (childrenLen + 1) / childrenLen;
    }
    this.tiles = [];
    this.client = null;
  }
  // remove child tiles
  removeChildren() {
    for (const tile of this.tiles) {
      tile.remove(true);
    }
    this.tiles = [];
  }
  // should be auto ran by driver but can be ran by engines too
  fixRelativeSizing() {
    let totalSize = 0;
    for (const tile of this.tiles) {
      totalSize += tile.relativeSize;
    }
    if (totalSize == 1) {
      return;
    }
    for (const tile of this.tiles) {
      tile.relativeSize /= totalSize;
    }
  }
};
var TilingEngine = class {
  constructor(config) {
    this.rootTile = new Tile();
    this.config = config;
  }
  // overrideable method if more internal engine stuff needs to be constructed
  initEngine() {
  }
};

// src/engine/layouts/btree.ts
var import_bi_map = __toESM(require_bi_map());
var import_queue = __toESM(require_queue());
var TreeNode = class _TreeNode {
  constructor() {
    this.parent = null;
    this.sibling = null;
    this.children = null;
    this.client = null;
    // ratio of child 1 to self
    this.sizeRatio = 0.5;
  }
  // splits tile
  split() {
    if (this.children != null)
      return;
    this.children = [new _TreeNode(), new _TreeNode()];
    this.children[0].parent = this;
    this.children[0].sibling = this.children[1];
    this.children[1].parent = this;
    this.children[1].sibling = this.children[0];
  }
  // removes self
  remove() {
    if (this.children != null || this.sibling == null || this.parent == null)
      return;
    if (this.sibling.children != null) {
      this.parent.children = this.sibling.children;
      for (const child of this.parent.children) {
        child.parent = this.parent;
      }
    } else {
      this.parent.client = this.sibling.client;
      this.parent.children = null;
    }
    this.parent = null;
    this.sibling.parent = null;
    this.sibling.sibling = null;
    this.sibling = null;
  }
};
var RootNode = class extends TreeNode {
  constructor() {
    super(...arguments);
    this.parent = null;
    this.sibling = null;
  }
  remove() {
    this.children = null;
    this.client = null;
  }
};
var BTreeEngine = class extends TilingEngine {
  constructor() {
    super(...arguments);
    this.engineCapability = 0 /* None */;
    this.rootNode = new RootNode();
    this.nodeMap = new import_bi_map.default();
  }
  // no engine settings for btree
  // (we dont save resizings through dbus saver right now)
  get engineSettings() {
    return {};
  }
  set engineSettings(_) {
  }
  buildLayout() {
    this.rootTile = new Tile();
    this.rootTile.layoutDirection = this.config.rotateLayout ? 2 : 1;
    this.nodeMap = new import_bi_map.default();
    let queue = new import_queue.default();
    queue.enqueue(this.rootNode);
    this.nodeMap.set(this.rootNode, this.rootTile);
    while (queue.size > 0) {
      const node = queue.dequeue();
      const tile = this.nodeMap.get(node);
      if (node.client != null) {
        tile.client = node.client;
      }
      if (node.children != null) {
        tile.split();
        this.nodeMap.set(node.children[0], tile.tiles[0]);
        this.nodeMap.set(node.children[1], tile.tiles[1]);
        tile.tiles[0].relativeSize = node.sizeRatio;
        tile.tiles[1].relativeSize = 1 - node.sizeRatio;
        queue.enqueue(node.children[0]);
        queue.enqueue(node.children[1]);
      }
    }
  }
  addClient(client) {
    let queue = new import_queue.default();
    queue.enqueue(this.rootNode);
    while (queue.size > 0) {
      const node = queue.dequeue();
      if (node.children == null) {
        if (node.client != null) {
          node.split();
          if (this.config.insertionPoint == 0 /* Left */) {
            node.children[0].client = client;
            node.children[1].client = node.client;
          } else {
            node.children[0].client = node.client;
            node.children[1].client = client;
          }
          node.client = null;
        } else {
          node.client = client;
        }
        return;
      } else {
        const children = Array.from(node.children);
        if (this.config.insertionPoint == 1 /* Right */) {
          children.reverse();
        }
        for (const child of children) {
          queue.enqueue(child);
        }
      }
    }
  }
  removeClient(client) {
    let queue = new import_queue.default();
    queue.enqueue(this.rootNode);
    let deleteQueue = [];
    while (queue.size > 0) {
      const node = queue.dequeue();
      if (node.client == client) {
        deleteQueue.push(node);
      }
      if (node.children != null) {
        for (const child of node.children) {
          queue.enqueue(child);
        }
      }
    }
    for (const node of deleteQueue) {
      node.remove();
    }
  }
  putClientInTile(client, tile, direction) {
    const node = this.nodeMap.inverse.get(tile);
    if (node == void 0) {
      this.addClient(client);
      return;
    }
    if (node.client == null) {
      node.client = client;
    } else {
      node.split();
      let putClientInZero = false;
      if (direction != void 0) {
        if (tile.layoutDirection == 1) {
          if (!(direction & 2 /* Right */)) {
            putClientInZero = true;
          }
        } else {
          if (direction & 1 /* Up */) {
            putClientInZero = true;
          }
        }
      }
      if (putClientInZero) {
        node.children[0].client = client;
        node.children[1].client = node.client;
      } else {
        node.children[0].client = node.client;
        node.children[1].client = client;
      }
      node.client = null;
    }
  }
  regenerateLayout() {
    for (const node of this.nodeMap.keys()) {
      const tile = this.nodeMap.get(node);
      if (tile.tiles.length == 2) {
        node.sizeRatio = tile.tiles[0].relativeSize;
      }
    }
  }
};

// src/engine/layouts/half.ts
var ClientBox = class {
  constructor(client) {
    this.client = client;
  }
};
var BoxIndex = class {
  constructor(engine, client) {
    this.left = false;
    this.right = false;
    for (let i = 0; i < engine.left.length; i += 1) {
      if (engine.left[i].client == client) {
        this.index = i;
        this.left = true;
        this.box = engine.left[i];
        return;
      }
    }
    for (let i = 0; i < engine.right.length; i += 1) {
      if (engine.right[i].client == client) {
        this.index = i;
        this.right = true;
        this.box = engine.right[i];
        return;
      }
    }
    throw new Error("Couldn't find box");
  }
};
var HalfEngine = class extends TilingEngine {
  constructor() {
    super(...arguments);
    this.engineCapability = 1 /* TranslateRotation */;
    this.tileMap = /* @__PURE__ */ new Map();
    this.left = [];
    this.right = [];
    // the ratio of left side to total space
    this.middleSplit = 0.5;
  }
  get engineSettings() {
    return {
      middleSplit: this.middleSplit
    };
  }
  set engineSettings(settings) {
    this.middleSplit = settings.middleSplit ?? 0.5;
  }
  buildLayout() {
    this.rootTile = new Tile();
    this.rootTile.layoutDirection = this.config.rotateLayout ? 2 : 1;
    if (this.left.length == 0 && this.right.length == 0) {
      return;
    } else if (this.left.length == 0 && this.right.length > 0) {
      for (const box of this.right) {
        const tile = this.rootTile.addChild();
        tile.client = box.client;
        this.tileMap.set(tile, box);
      }
    } else if (this.left.length > 0 && this.right.length == 0) {
      for (const box of this.left) {
        const tile = this.rootTile.addChild();
        tile.client = box.client;
        this.tileMap.set(tile, box);
      }
    } else {
      this.rootTile.split();
      const left = this.rootTile.tiles[0];
      const right = this.rootTile.tiles[1];
      left.relativeSize = this.middleSplit;
      right.relativeSize = 1 - this.middleSplit;
      for (const box of this.left) {
        const tile = left.addChild();
        tile.client = box.client;
        this.tileMap.set(tile, box);
      }
      for (const box of this.right) {
        const tile = right.addChild();
        tile.client = box.client;
        this.tileMap.set(tile, box);
      }
    }
  }
  addClient(client) {
    if (this.config.insertionPoint == 0 /* Left */) {
      if (this.right.length == 0) {
        this.right.push(new ClientBox(client));
      } else {
        this.left.push(new ClientBox(client));
      }
    } else {
      if (this.left.length == 0) {
        this.left.push(new ClientBox(client));
      } else {
        this.right.push(new ClientBox(client));
      }
    }
  }
  removeClient(client) {
    let box;
    try {
      box = new BoxIndex(this, client);
    } catch (e) {
      throw e;
    }
    if (box.right) {
      this.right.splice(box.index, 1);
      if (this.right.length == 0 && this.left.length > 1) {
        this.right.push(this.left.splice(0, 1)[0]);
      }
    } else {
      this.left.splice(box.index, 1);
      if (this.left.length == 0 && this.right.length > 1) {
        this.left.push(this.right.splice(0, 1)[0]);
      }
    }
  }
  // default to inserting below
  putClientInTile(client, tile, direction = 4 /* Vertical */) {
    const clientBox = new ClientBox(client);
    let targetBox;
    const box = this.tileMap.get(tile);
    if (box == void 0) {
      this.addClient(client);
      return;
    }
    targetBox = new BoxIndex(this, box.client);
    const targetArr = targetBox.left ? this.left : this.right;
    if (direction & 1 /* Up */) {
      targetArr.splice(targetBox.index, 0, clientBox);
    } else {
      targetArr.splice(targetBox.index + 1, 0, clientBox);
    }
  }
  regenerateLayout() {
    if (this.rootTile.tiles.length == 2) {
      this.middleSplit = this.rootTile.tiles[0].relativeSize;
    }
  }
};

// src/engine/layouts/threecolumn.ts
var ClientBox2 = class {
  constructor(client) {
    this.client = client;
  }
};
var BoxIndex2 = class {
  constructor(engine, client) {
    for (let i = 0; i < engine.rows.length; i += 1) {
      const row = engine.rows[i];
      for (let j = 0; j < row.length; j += 1) {
        if (row[j].client == client) {
          this.index = j;
          this.row = i;
          this.box = row[j];
          return;
        }
      }
    }
    throw new Error("Couldn't find box");
  }
};
var ThreeColumnEngine = class extends TilingEngine {
  constructor() {
    super(...arguments);
    this.engineCapability = 1 /* TranslateRotation */;
    this.tileMap = /* @__PURE__ */ new Map();
    this.rows = [[], [], []];
    this.leftSize = 0.25;
    this.rightSize = 0.25;
  }
  get engineSettings() {
    return {
      leftSize: this.leftSize,
      rightSize: this.rightSize
    };
  }
  set engineSettings(settings) {
    this.leftSize = settings.leftSize ?? 0.25;
    this.rightSize = settings.rightSize ?? 0.25;
  }
  buildLayout() {
    this.rootTile = new Tile();
    this.rootTile.layoutDirection = this.config.rotateLayout ? 2 : 1;
    let middleSize = 1;
    if (this.rows[2].length != 0) {
      middleSize -= this.rightSize;
    }
    if (this.rows[0].length != 0) {
      middleSize -= this.leftSize;
    }
    for (let i = 0; i < this.rows.length; i += 1) {
      const row = this.rows[i];
      if (row.length == 0) {
        continue;
      }
      const rowRoot = this.rootTile.addChild(false);
      if (i == 0) {
        rowRoot.relativeSize = this.leftSize;
      } else if (i == 1) {
        rowRoot.relativeSize = middleSize;
      } else {
        rowRoot.relativeSize = this.rightSize;
      }
      for (const box of row) {
        const tile = rowRoot.addChild();
        tile.client = box.client;
        this.tileMap.set(tile, box);
      }
    }
  }
  addClient(client) {
    if (this.rows[1].length == 0) {
      this.rows[1].push(new ClientBox2(client));
      return;
    }
    if (this.config.insertionPoint == 0 /* Left */) {
      if (this.rows[0].length > this.rows[2].length) {
        this.rows[2].push(new ClientBox2(client));
      } else {
        this.rows[0].push(new ClientBox2(client));
      }
    } else {
      if (this.rows[2].length > this.rows[0].length) {
        this.rows[0].push(new ClientBox2(client));
      } else {
        this.rows[2].push(new ClientBox2(client));
      }
    }
  }
  removeClient(client) {
    let box;
    try {
      box = new BoxIndex2(this, client);
    } catch (e) {
      throw e;
    }
    const row = this.rows[box.row];
    row.splice(box.index, 1);
  }
  putClientInTile(client, tile, direction) {
    const clientBox = new ClientBox2(client);
    let targetBox;
    const box = this.tileMap.get(tile);
    if (box == void 0) {
      this.addClient(client);
      return;
    }
    targetBox = new BoxIndex2(this, box.client);
    const targetArr = this.rows[targetBox.row];
    if (direction == null || direction & 1 /* Up */) {
      targetArr.splice(targetBox.index, 0, clientBox);
    } else {
      targetArr.splice(targetBox.index + 1, 0, clientBox);
    }
  }
  regenerateLayout() {
    if (this.rootTile.tiles.length < 2 || this.rootTile.layoutDirection == 2 /* Vertical */) {
      return;
    }
    if (this.rootTile.tiles.length == 2) {
      if (this.rows[0].length == 0) {
        this.rightSize = this.rootTile.tiles[1].relativeSize;
      } else if (this.rows[2].length == 0) {
        this.leftSize = this.rootTile.tiles[0].relativeSize;
      }
    } else if (this.rootTile.tiles.length == 3) {
      this.rightSize = this.rootTile.tiles[2].relativeSize;
      this.leftSize = this.rootTile.tiles[0].relativeSize;
    }
  }
};

// src/engine/layouts/monocle.ts
var MonocleEngine = class extends TilingEngine {
  constructor() {
    super(...arguments);
    this.engineCapability = 0 /* None */;
    this.clients = [];
  }
  get engineSettings() {
    return {};
  }
  set engineSettings(_) {
  }
  buildLayout() {
    this.rootTile = new Tile();
    for (const client of this.clients) {
      this.rootTile.clients.push(client);
    }
  }
  addClient(client) {
    if (!this.clients.includes(client)) {
      if (this.config.insertionPoint == 1 /* Right */) {
        this.clients.push(client);
      } else {
        this.clients.splice(0, 0, client);
      }
    }
    return;
  }
  removeClient(client) {
    const index = this.clients.indexOf(client);
    if (index >= 0) {
      this.clients.splice(index, 1);
    }
  }
  // handle switching order of windows through side-based insertion
  // inserting above/right puts window on top, inserting
  putClientInTile(client, _tile, direction) {
    if (this.clients.includes(client)) {
      return;
    }
    if (direction == void 0) {
      this.addClient(client);
      return;
    }
    if (direction & 1 /* Up */ && direction & 4 /* Vertical */ || direction & 2 /* Right */ && !(direction & 4 /* Vertical */)) {
      this.clients.push(client);
    } else {
      const lastClient = this.clients.pop();
      if (lastClient == void 0) {
        this.clients.push(client);
      } else {
        this.clients.splice(0, 0, lastClient, client);
      }
    }
  }
  regenerateLayout() {
    return;
  }
};

// src/engine/layouts/kwin.ts
var import_queue2 = __toESM(require_queue());
var KwinEngine = class extends TilingEngine {
  constructor() {
    super(...arguments);
    // tilesmutable moves all processing work to driver
    this.engineCapability = 2 /* TilesMutable */ | 4 /* UntiledByDefault */;
  }
  get engineSettings() {
    return {};
  }
  set engineSettings(_) {
  }
  buildLayout() {
    return;
  }
  addClient() {
    return;
  }
  removeClient(client) {
    const queue = new import_queue2.default();
    let tile = this.rootTile;
    while (tile != void 0) {
      const index = tile.clients.indexOf(client);
      if (index >= -1) {
        tile.clients.splice(index, 1);
        return;
      }
      for (const child of tile.tiles) {
        queue.enqueue(child);
      }
      tile = queue.dequeue();
    }
  }
  putClientInTile(client, tile, _direction) {
    if (!tile.clients.includes(client)) {
      tile.clients.push(client);
    }
  }
  regenerateLayout() {
    return;
  }
};

// src/engine/index.ts
var Client6 = class {
  constructor(window) {
    this.name = window.resourceClass;
    this.minSize = window.minSize;
  }
};
var TilingEngineFactory = class {
  constructor(config) {
    this.config = config;
  }
  newEngine(optConfig) {
    let config = optConfig;
    if (config == void 0) {
      config = {
        engineType: this.config.engineType,
        insertionPoint: this.config.insertionPoint,
        rotateLayout: this.config.rotateLayout,
        engineSettings: {}
      };
    }
    const t = config.engineType % 5 /* _loop */;
    let engine;
    switch (t) {
      case 0 /* BTree */:
        engine = new BTreeEngine(config);
        break;
      case 1 /* Half */:
        engine = new HalfEngine(config);
        break;
      case 2 /* ThreeColumn */:
        engine = new ThreeColumnEngine(config);
        break;
      case 3 /* Monocle */:
        engine = new MonocleEngine(config);
        break;
      case 4 /* Kwin */:
        engine = new KwinEngine(config);
        break;
      default:
        throw new Error("Engine not found for engine type " + t);
    }
    engine.initEngine();
    engine.engineSettings = config.engineSettings ?? {};
    return engine;
  }
};

// src/util/config.ts
var Config = class {
  constructor(kwinApi) {
    this.debug = false;
    this.tilePopups = false;
    this.filterProcess = [
      "krunner",
      "yakuake",
      "kded",
      "polkit",
      "plasmashell"
    ];
    this.filterCaption = [];
    this.timerDelay = 10;
    this.keepTiledBelow = true;
    this.borders = 1 /* NoTiled */;
    this.maximizeSingle = false;
    this.resizeAmount = 10;
    this.saveOnTileEdit = false;
    this.engineType = 0 /* BTree */;
    this.insertionPoint = 0 /* Left */;
    this.rotateLayout = true;
    this.readConfigFn = kwinApi.readConfig;
    this.readConfig();
  }
  readConfig() {
    let rc = this.readConfigFn;
    if (rc == void 0) {
      return;
    }
    this.debug = rc("Debug", false);
    this.tilePopups = rc("TilePopups", false);
    this.filterProcess = rc(
      "FilterProcess",
      "krunner, yakuake, kded, polkit, plasmashell"
    ).split(",").map((x) => x.trim());
    this.filterCaption = rc("FilterCaption", "").split(",").map((x) => x.trim());
    this.timerDelay = rc("TimerDelay", 10);
    this.keepTiledBelow = rc("KeepTiledBelow", true);
    this.borders = rc("Borders", 1 /* NoTiled */);
    this.maximizeSingle = rc("MaximizeSingle", false);
    this.resizeAmount = rc("ResizeAmount", 10);
    this.saveOnTileEdit = rc("SaveOnTileEdit", false);
    this.engineType = rc("EngineType", 0 /* BTree */);
    this.insertionPoint = rc("InsertionPoint", 0 /* Left */);
    this.rotateLayout = rc("RotateLayout", false);
  }
};

// src/driver/driver.ts
var import_bi_map2 = __toESM(require_bi_map());
var import_queue3 = __toESM(require_queue());
var TilingDriver = class {
  constructor(engine, engineType, ctrl, engineFactory) {
    this.tiles = new import_bi_map2.default();
    this.clients = new import_bi_map2.default();
    // windows that have no associated tile but are still in an engine go here
    this.untiledWindows = [];
    this.engine = engine;
    this.engineType = engineType;
    this.ctrl = ctrl;
    this.engineFactory = engineFactory;
    this.logger = ctrl.logger;
    this.config = ctrl.config;
  }
  get engineConfig() {
    return {
      engineType: this.engineType,
      insertionPoint: this.engine.config.insertionPoint,
      rotateLayout: this.engine.config.rotateLayout,
      engineSettings: this.engine.engineSettings
    };
  }
  set engineConfig(config) {
    if (config.engineType != this.engineType) {
      this.switchEngine(
        this.engineFactory.newEngine(config),
        config.engineType
      );
    }
    this.engine.config.insertionPoint = config.insertionPoint;
    this.engine.config.rotateLayout = config.rotateLayout;
    if (config.engineSettings != void 0) {
      this.engine.engineSettings = config.engineSettings;
    }
    try {
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
  switchEngine(engine, engineType) {
    this.engine = engine;
    this.engineType = engineType;
    try {
      for (const window of this.clients.keys()) {
        if (!this.untiledWindows.includes(window)) {
          if (this.engine.engineCapability & 4 /* UntiledByDefault */) {
            this.untiledWindows.push(window);
          } else {
            this.engine.addClient(this.clients.get(window));
          }
        }
      }
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
  buildLayout(rootTile) {
    while (rootTile.tiles.length > 0) {
      rootTile.tiles[0].remove();
    }
    this.tiles.clear();
    let realRootTile = this.engine.rootTile;
    while (realRootTile.tiles.length == 1 && realRootTile.clients.length == 0) {
      realRootTile = realRootTile.tiles[0];
    }
    this.tiles.set(rootTile, realRootTile);
    if (realRootTile.clients.length != 0 && this.config.maximizeSingle) {
      for (let i = realRootTile.clients.length - 1; i >= 0; i -= 1) {
        const client = realRootTile.clients[i];
        const window = this.clients.inverse.get(client);
        if (window == void 0) {
          this.logger.error("Window undefined");
          continue;
        }
        window.tile = null;
        this.ctrl.windowExtensions.get(window).isSingleMaximized = true;
        window.setMaximize(true, true);
        this.ctrl.workspace.raiseWindow(window);
      }
      return;
    }
    const queue = new import_queue3.default();
    queue.enqueue(realRootTile);
    while (queue.size > 0) {
      const tile = queue.dequeue();
      const kwinTile = this.tiles.inverse.get(tile);
      this.ctrl.managedTiles.add(kwinTile);
      kwinTile.layoutDirection = tile.layoutDirection;
      const horizontal = kwinTile.layoutDirection == 1 /* Horizontal */;
      const tilesLen = tile.tiles.length;
      tile.fixRelativeSizing();
      if (tilesLen > 1) {
        for (let i = 0; i < tilesLen; i += 1) {
          if (i == 0) {
            kwinTile.split(tile.layoutDirection);
          } else if (i > 1) {
            kwinTile.tiles[i - 1].split(tile.layoutDirection);
          }
          const childKwinTile = kwinTile.tiles[i];
          const childTile = tile.tiles[i];
          this.tiles.set(childKwinTile, childTile);
          if (horizontal && i > 0) {
            kwinTile.tiles[i - 1].relativeGeometry.width = kwinTile.relativeGeometry.width * tile.tiles[i - 1].relativeSize;
          } else if (i > 0) {
            kwinTile.tiles[i - 1].relativeGeometry.height = kwinTile.relativeGeometry.height * tile.tiles[i - 1].relativeSize;
          }
          queue.enqueue(childTile);
        }
      } else if (tilesLen == 1) {
        this.tiles.set(kwinTile, tile.tiles[0]);
        queue.enqueue(tile.tiles[0]);
      }
      for (let i = tile.clients.length - 1; i >= 0; i -= 1) {
        const client = tile.clients[i];
        const window = this.clients.inverse.get(client);
        if (window == void 0) {
          this.logger.error("Client", client.name, "does not exist");
          return;
        }
        const extensions = this.ctrl.windowExtensions.get(window);
        window.minimized = false;
        window.fullScreen = false;
        window.setMaximize(false, false);
        extensions.isSingleMaximized = false;
        window.tile = kwinTile;
        extensions.lastTiledLocation = GPoint.centerOfRect(
          kwinTile.absoluteGeometry
        );
        this.ctrl.workspace.raiseWindow(window);
      }
      this.fixSizing(tile, kwinTile);
    }
  }
  fixSizing(tile, kwinTile) {
    if (tile.parent == null || kwinTile.parent == null) {
      return;
    }
    let index = tile.parent.tiles.indexOf(tile);
    let parentIndex = tile.parent.parent != null ? tile.parent.parent.tiles.indexOf(tile.parent) : null;
    const requestedSize = new GSize();
    requestedSize.fitSize(tile.requestedSize);
    for (const client of tile.clients) {
      const window = this.clients.inverse.get(client);
      if (window == void 0) {
        continue;
      }
      requestedSize.fitSize(window.minSize);
    }
    const horizontal = kwinTile.parent.layoutDirection == 1 /* Horizontal */;
    if (requestedSize.width > kwinTile.absoluteGeometryInScreen.width) {
      let diff = requestedSize.width - kwinTile.absoluteGeometryInScreen.width;
      if (horizontal) {
        if (index == 0) {
          kwinTile.resizeByPixels(diff, 4 /* RightEdge */);
        } else {
          kwinTile.resizeByPixels(-diff, 2 /* LeftEdge */);
        }
      } else if (parentIndex != null) {
        if (parentIndex == 0) {
          kwinTile.parent.resizeByPixels(diff, 4 /* RightEdge */);
        } else {
          kwinTile.parent.resizeByPixels(-diff, 2 /* LeftEdge */);
        }
      }
    }
    if (requestedSize.height > kwinTile.absoluteGeometryInScreen.height) {
      let diff = requestedSize.height - kwinTile.absoluteGeometryInScreen.height;
      if (!horizontal) {
        if (index == 0) {
          kwinTile.resizeByPixels(diff, 8 /* BottomEdge */);
        } else {
          kwinTile.resizeByPixels(
            -diff,
            1 /* TopEdge */
          );
        }
      } else if (parentIndex != null) {
        if (parentIndex == 0) {
          kwinTile.parent.resizeByPixels(diff, 8 /* BottomEdge */);
        } else {
          kwinTile.parent.resizeByPixels(-diff, 1 /* TopEdge */);
        }
      }
    }
  }
  untileWindow(window) {
    if (this.untiledWindows.includes(window)) {
      return;
    }
    const client = this.clients.get(window);
    if (client == void 0) {
      return;
    }
    this.untiledWindows.push(window);
    try {
      this.engine.removeClient(client);
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
  addWindow(window) {
    if (!this.clients.has(window)) {
      this.clients.set(window, new Client6(window));
      if (this.engine.engineCapability & 4 /* UntiledByDefault */) {
        this.untiledWindows.push(window);
        return;
      }
    }
    let index = this.untiledWindows.indexOf(window);
    if (index >= 0) {
      this.untiledWindows.splice(index, 1)[0];
    }
    const client = this.clients.get(window);
    let activeTile = null;
    if (this.engine.config.insertionPoint == 2 /* Active */) {
      const activeWindow = this.ctrl.workspaceExtensions.lastActiveWindow;
      if (activeWindow != null && activeWindow.tile != null) {
        activeTile = this.tiles.get(activeWindow.tile) ?? null;
      }
    }
    try {
      if (activeTile == null) {
        this.engine.addClient(client);
      } else {
        this.engine.putClientInTile(client, activeTile);
      }
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
  removeWindow(window) {
    const client = this.clients.get(window);
    if (client == void 0) {
      return;
    }
    this.clients.delete(window);
    if (this.untiledWindows.includes(window)) {
      this.untiledWindows.splice(this.untiledWindows.indexOf(window), 1);
      return;
    }
    try {
      this.engine.removeClient(client);
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
  putWindowInTile(window, kwinTile, direction) {
    let tile = this.tiles.get(kwinTile);
    if (tile == void 0) {
      this.logger.error(
        "Tile",
        kwinTile.absoluteGeometry,
        "not registered"
      );
      return;
    }
    if (!this.clients.has(window)) {
      this.clients.set(window, new Client6(window));
    }
    const client = this.clients.get(window);
    let index = this.untiledWindows.indexOf(window);
    if (index >= 0) {
      this.untiledWindows.splice(index, 1)[0];
    }
    try {
      let rotatedDirection = direction;
      if (rotatedDirection != null && this.engine.config.rotateLayout && (this.engine.engineCapability & 1 /* TranslateRotation */) == 1 /* TranslateRotation */) {
        rotatedDirection = new DirectionTools(
          rotatedDirection
        ).rotateCw();
        this.logger.debug(
          "Insertion direction rotated to",
          rotatedDirection
        );
      }
      this.engine.putClientInTile(client, tile, rotatedDirection);
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
  regenerateLayout(rootTile) {
    const queue = new import_queue3.default();
    queue.enqueue(rootTile);
    while (queue.size > 0) {
      const kwinTile = queue.dequeue();
      const tile = this.tiles.get(kwinTile);
      if (tile == void 0) {
        this.logger.error(
          "Tile",
          kwinTile.absoluteGeometry,
          "not registered"
        );
        continue;
      }
      const tilesToSetSize = [tile];
      let parentTmp = tile.parent;
      while (parentTmp != null && parentTmp.tiles.length == 1) {
        tilesToSetSize.push(parentTmp);
        parentTmp = parentTmp.parent;
      }
      for (const variableAlsoNamedTile of tilesToSetSize) {
        variableAlsoNamedTile.requestedSize = GSize.fromRect(
          kwinTile.absoluteGeometry
        );
        variableAlsoNamedTile.relativeSize = 1;
      }
      const highestTile = tilesToSetSize[tilesToSetSize.length - 1];
      if (kwinTile.parent != null && kwinTile.parent.layoutDirection == 1 /* Horizontal */) {
        highestTile.relativeSize = kwinTile.relativeGeometry.width / kwinTile.parent.relativeGeometry.width;
      } else if (kwinTile.parent != null) {
        highestTile.relativeSize = kwinTile.relativeGeometry.height / kwinTile.parent.relativeGeometry.height;
      }
      if ((this.engine.engineCapability & 2 /* TilesMutable */) == 2 /* TilesMutable */) {
        for (const child of tile.tiles) {
          if (this.tiles.inverse.get(child) == null) {
            this.tiles.inverse.delete(child);
            child.remove();
          }
        }
        for (const child of kwinTile.tiles) {
          if (!this.tiles.has(child)) {
            const newTile = tile.addChild();
            this.tiles.set(child, newTile);
          }
        }
      }
      for (const child of kwinTile.tiles) {
        queue.enqueue(child);
      }
    }
    try {
      this.engine.regenerateLayout();
      this.engine.buildLayout();
    } catch (e) {
      this.logger.error(e);
    }
  }
};

// src/controller/desktop.ts
var Desktop = class {
  constructor(desktop, activity, output) {
    this.desktop = desktop;
    this.activity = activity;
    this.output = output;
  }
  toRawDesktop() {
    return {
      desktop: this.desktop.id,
      activity: this.activity,
      output: this.output.name
    };
  }
  toString() {
    return JSON.stringify(this.toRawDesktop());
  }
};
var DesktopFactory = class {
  constructor(workspace) {
    this.desktopMap = /* @__PURE__ */ new Map();
    this.outputMap = /* @__PURE__ */ new Map();
    this.workspace = workspace;
    this.desktopsChanged();
    this.screensChanged();
    this.workspace.desktopsChanged.connect(this.desktopsChanged.bind(this));
    this.workspace.screensChanged.connect(this.screensChanged.bind(this));
  }
  createDesktopsFromWindow(window) {
    const ret = [];
    let desktops;
    if (window.onAllDesktops) {
      desktops = this.workspace.desktops;
    } else {
      desktops = window.desktops;
    }
    for (const desktop of desktops) {
      for (const activity of window.activities) {
        ret.push(new Desktop(desktop, activity, window.output));
      }
    }
    return ret;
  }
  desktopsChanged() {
    this.desktopMap.clear();
    for (const desktop of this.workspace.desktops) {
      this.desktopMap.set(desktop.id, desktop);
    }
  }
  screensChanged() {
    this.outputMap.clear();
    for (const output of this.workspace.screens) {
      this.outputMap.set(output.name, output);
    }
  }
  createDesktop(desktop, activity, output) {
    return new Desktop(desktop, activity, output);
  }
  createDefaultDesktop() {
    return new Desktop(
      this.workspace.currentDesktop,
      this.workspace.currentActivity,
      this.workspace.activeScreen
    );
  }
  createDesktopFromStrings(desktop) {
    const virtualDesktop = this.desktopMap.get(desktop.desktop);
    const output = this.outputMap.get(desktop.output);
    if (virtualDesktop == void 0 || output == void 0 || !this.workspace.activities.includes(desktop.activity)) {
      throw new Error("Tried to create a desktop that does not exist!");
    }
    return new Desktop(virtualDesktop, desktop.activity, output);
  }
  createAllDesktops() {
    const ret = [];
    for (const output of this.workspace.screens) {
      for (const activity of this.workspace.activities) {
        for (const desktop of this.workspace.desktops) {
          ret.push(new Desktop(desktop, activity, output));
        }
      }
    }
    return ret;
  }
  createVisibleDesktops() {
    const ret = [];
    for (const output of this.workspace.screens) {
      ret.push(
        new Desktop(
          this.workspace.currentDesktop,
          this.workspace.currentActivity,
          output
        )
      );
    }
    return ret;
  }
};

// src/driver/index.ts
var DriverManager = class {
  constructor(c) {
    this.drivers = /* @__PURE__ */ new Map();
    this.rootTileCallbacks = /* @__PURE__ */ new Map();
    this.buildingLayout = false;
    this.resizingLayout = false;
    this.ctrl = c;
    this.engineFactory = new TilingEngineFactory(this.ctrl.config);
    this.logger = c.logger;
    this.config = c.config;
  }
  init() {
    const c = this.ctrl;
    c.workspace.screensChanged.connect(this.generateDrivers.bind(this));
    c.workspace.desktopsChanged.connect(this.generateDrivers.bind(this));
    c.workspace.activitiesChanged.connect(this.generateDrivers.bind(this));
    this.generateDrivers();
  }
  generateDrivers() {
    const currentDesktops = [];
    for (const desktop of this.drivers.keys()) {
      currentDesktops.push(desktop);
    }
    for (const desktop of this.ctrl.desktopFactory.createAllDesktops()) {
      const desktopString = desktop.toString();
      const index = currentDesktops.indexOf(desktopString);
      if (index == -1) {
        this.logger.debug(
          "Creating new engine for desktop",
          desktopString
        );
        let engineType = this.config.engineType;
        const config = {
          engineType,
          insertionPoint: this.config.insertionPoint,
          rotateLayout: this.config.rotateLayout,
          engineSettings: {}
        };
        const engine = this.engineFactory.newEngine(config);
        const driver = new TilingDriver(
          engine,
          engineType,
          this.ctrl,
          this.engineFactory
        );
        this.drivers.set(desktopString, driver);
        this.ctrl.dbusManager.getSettings(
          desktopString,
          this.setEngineConfig.bind(this, desktop)
        );
      } else {
        currentDesktops.splice(index, 1);
      }
    }
    for (const desktop of currentDesktops) {
      this.drivers.delete(desktop);
    }
    for (const tile of this.rootTileCallbacks.keys()) {
      let remove = true;
      for (const output of this.ctrl.workspace.screens) {
        if (this.ctrl.workspace.tilingForScreen(output).rootTile == tile) {
          remove = false;
          break;
        }
      }
      if (remove && this.rootTileCallbacks.has(tile)) {
        this.rootTileCallbacks.get(tile).destroy();
        this.rootTileCallbacks.delete(tile);
      }
    }
    for (const output of this.ctrl.workspace.screens) {
      const rootTile = this.ctrl.workspace.tilingForScreen(output).rootTile;
      if (this.ctrl.managedTiles.has(rootTile)) {
        continue;
      }
      this.ctrl.managedTiles.add(rootTile);
      const timer = this.ctrl.qmlObjects.root.createTimer();
      timer.interval = this.config.timerDelay;
      timer.triggered.connect(
        this.layoutModifiedCallback.bind(this, rootTile, output)
      );
      timer.repeat = false;
      this.rootTileCallbacks.set(rootTile, timer);
      rootTile.layoutModified.connect(
        this.layoutModified.bind(this, rootTile)
      );
    }
  }
  layoutModified(tile) {
    if (this.buildingLayout) {
      return;
    }
    this.resizingLayout = true;
    const timer = this.rootTileCallbacks.get(tile);
    if (timer == void 0) {
      this.logger.error(
        "Callback not registered for root tile",
        tile.absoluteGeometry
      );
      return;
    }
    timer.restart();
  }
  layoutModifiedCallback(tile, output) {
    this.logger.debug("Layout modified for tile", tile.absoluteGeometry);
    const desktop = new Desktop(
      this.ctrl.workspace.currentDesktop,
      this.ctrl.workspace.currentActivity,
      output
    );
    const driver = this.drivers.get(desktop.toString());
    driver.regenerateLayout(tile);
    if (this.config.saveOnTileEdit) {
      this.ctrl.dbusManager.setSettings(
        desktop.toString(),
        driver.engineConfig
      );
    }
    this.resizingLayout = false;
  }
  applyTiled(window) {
    this.ctrl.windowExtensions.get(window).isTiled = true;
    if (this.config.keepTiledBelow) {
      window.keepBelow = true;
    }
    if (this.config.borders == 1 /* NoTiled */ || this.config.borders == 2 /* Selected */) {
      if (!(this.config.borders == 2 /* Selected */ && this.ctrl.workspace.activeWindow == window)) {
        window.noBorder = true;
      }
    }
  }
  applyUntiled(window) {
    const extensions = this.ctrl.windowExtensions.get(window);
    extensions.isTiled = false;
    extensions.isSingleMaximized = false;
    if (this.config.keepTiledBelow) {
      window.keepBelow = false;
    }
    if (this.config.borders == 1 /* NoTiled */ || this.config.borders == 2 /* Selected */) {
      window.noBorder = false;
    }
  }
  rebuildLayout(output) {
    this.buildingLayout = true;
    let desktops;
    if (output == void 0) {
      desktops = this.ctrl.desktopFactory.createVisibleDesktops();
    } else {
      desktops = [
        new Desktop(
          this.ctrl.workspace.currentDesktop,
          this.ctrl.workspace.currentActivity,
          output
        )
      ];
    }
    this.logger.debug("Rebuilding layout for desktops", desktops);
    for (const desktop of desktops) {
      const driver = this.drivers.get(desktop.toString());
      for (const window of driver.clients.keys()) {
        if (!driver.untiledWindows.includes(window)) {
          this.applyTiled(window);
        }
      }
      driver.buildLayout(
        this.ctrl.workspace.tilingForScreen(desktop.output).rootTile
      );
      for (const window of driver.untiledWindows) {
        const extensions = this.ctrl.windowExtensions.get(window);
        if (!extensions.isTiled) {
          continue;
        }
        let fullscreen = false;
        if (window.fullScreen && extensions.isTiled) {
          window.fullScreen = false;
          fullscreen = true;
        }
        const wasSingleMaximized = extensions.isSingleMaximized;
        this.applyUntiled(window);
        window.tile = null;
        if (wasSingleMaximized) {
          window.setMaximize(false, false);
        }
        if (fullscreen) {
          window.fullScreen = true;
        }
      }
    }
    this.buildingLayout = false;
  }
  untileWindow(window, desktops) {
    if (desktops == void 0) {
      desktops = this.ctrl.desktopFactory.createDesktopsFromWindow(window);
    }
    this.logger.debug(
      "Untiling window",
      window.resourceClass,
      "on desktops",
      desktops
    );
    for (const desktop of desktops) {
      this.drivers.get(desktop.toString()).untileWindow(window);
    }
  }
  addWindow(window, desktops) {
    if (desktops == void 0) {
      desktops = this.ctrl.desktopFactory.createDesktopsFromWindow(window);
    }
    this.logger.debug(
      "Adding window",
      window.resourceClass,
      "to desktops",
      desktops
    );
    for (const desktop of desktops) {
      this.drivers.get(desktop.toString()).addWindow(window);
    }
  }
  removeWindow(window, desktops) {
    if (desktops == void 0) {
      desktops = this.ctrl.desktopFactory.createDesktopsFromWindow(window);
    }
    this.logger.debug(
      "Removing window",
      window.resourceClass,
      "from desktops",
      desktops
    );
    for (const desktop of desktops) {
      this.drivers.get(desktop.toString()).removeWindow(window);
    }
  }
  putWindowInTile(window, tile, direction) {
    const desktop = this.ctrl.desktopFactory.createDefaultDesktop();
    desktop.output = window.output;
    this.logger.debug(
      "Putting client",
      window.resourceClass,
      "in tile",
      tile.absoluteGeometry,
      "with direction",
      direction,
      "on desktop",
      desktop
    );
    this.drivers.get(desktop.toString()).putWindowInTile(window, tile, direction);
  }
  getEngineConfig(desktop) {
    this.logger.debug("Getting engine config for desktop", desktop);
    return this.drivers.get(desktop.toString()).engineConfig;
  }
  setEngineConfig(desktop, config) {
    this.logger.debug("Setting engine config for desktop", desktop);
    const driver = this.drivers.get(desktop.toString());
    driver.engineConfig = config;
    this.ctrl.dbusManager.setSettings(
      desktop.toString(),
      driver.engineConfig
    );
    this.rebuildLayout(desktop.output);
  }
  removeEngineConfig(desktop) {
    this.logger.debug("Removing engine config for desktop", desktop);
    const config = {
      engineType: this.config.engineType,
      insertionPoint: this.config.insertionPoint,
      rotateLayout: this.config.rotateLayout,
      engineSettings: {}
    };
    this.drivers.get(desktop.toString()).engineConfig = config;
    this.ctrl.dbusManager.removeSettings(desktop.toString());
    this.rebuildLayout(desktop.output);
  }
};

// src/controller/actions/dbus.ts
var DBusManager = class {
  constructor(ctrl) {
    this.isConnected = false;
    this.connectedDesktops = /* @__PURE__ */ new Set();
    this.logger = ctrl.logger;
    const dbus = ctrl.qmlObjects.dbus;
    this.existsCall = dbus.getExists();
    this.getSettingsCall = dbus.getGetSettings();
    this.setSettingsCall = dbus.getSetSettings();
    this.removeSettingsCall = dbus.getRemoveSettings();
    this.existsCall.finished.connect(this.existsCallback.bind(this));
    this.existsCall.call();
  }
  existsCallback() {
    this.isConnected = true;
    this.logger.debug("DBus connected");
  }
  getSettingsCallback(desktop, setEngineConfig, args) {
    if (args[0] != desktop) {
      return;
    }
    if (args[1].length == 0) {
      return;
    }
    let config = JSON.parse(args[1]);
    setEngineConfig(config);
  }
  setSettings(desktop, config) {
    if (!this.isConnected) {
      return;
    }
    const stringConfig = JSON.stringify(config);
    this.logger.debug(
      "Setting settings over dbus for desktop",
      desktop,
      "to",
      stringConfig
    );
    this.setSettingsCall.arguments = [desktop, stringConfig];
    this.setSettingsCall.call();
  }
  getSettings(desktop, fn) {
    if (!this.isConnected) {
      return;
    }
    this.logger.debug("Getting settings over dbus for desktop", desktop);
    if (!this.connectedDesktops.has(desktop)) {
      this.getSettingsCall.finished.connect(
        this.getSettingsCallback.bind(this, desktop, fn)
      );
      this.connectedDesktops.add(desktop);
    }
    this.getSettingsCall.arguments = [desktop];
    this.getSettingsCall.call();
  }
  removeSettings(desktop) {
    if (!this.isConnected) {
      return;
    }
    this.logger.debug("Removing settings over dbus for desktop", desktop);
    this.removeSettingsCall.arguments = [desktop];
    this.removeSettingsCall.call();
  }
};

// src/controller/extensions.ts
var WorkspaceExtensions = class {
  //private logger: Log;
  constructor(workspace) {
    this.lastActiveWindow = null;
    this.currentActiveWindow = null;
    this.workspace = workspace;
    this.currentActivity = this.workspace.currentActivity;
    this.currentDesktop = this.workspace.currentDesktop;
    this.lastActivity = this.currentActivity;
    this.lastDesktop = this.currentDesktop;
    this.currentActiveWindow = this.workspace.activeWindow;
    this.workspace.currentActivityChanged.connect(this.repoll.bind(this));
    this.workspace.currentDesktopChanged.connect(this.repoll.bind(this));
    this.workspace.windowActivated.connect(this.windowActivated.bind(this));
  }
  // this flickers to null and then back so account for null
  windowActivated(window) {
    if (window == null) {
      return;
    }
    this.lastActiveWindow = this.currentActiveWindow;
    this.currentActiveWindow = window;
  }
  repoll() {
    this.lastActivity = this.currentActivity;
    this.lastDesktop = this.currentDesktop;
    this.currentActivity = this.workspace.currentActivity;
    this.currentDesktop = this.workspace.currentDesktop;
  }
};
var WindowExtensions = class {
  constructor(window, desktopFactory) {
    // only store state of full maximization (who maximizes only directionally?)
    this.maximized = false;
    this.previousDesktops = [];
    this.previousDesktopsInternal = [];
    this.isTiled = false;
    // not is in a tile, but is registered in engine
    this.wasTiled = false;
    // windows that were tiled when they could be (minimized/maximized/fullscreen)
    this.lastTiledLocation = null;
    this.clientHooks = null;
    this.isSingleMaximized = false;
    this.window = window;
    this.desktopFactory = desktopFactory;
    window.maximizedAboutToChange.connect(
      (m) => this.maximized = m == 3 /* MaximizeFull */
    );
    window.desktopsChanged.connect(this.previousDesktopsChanged.bind(this));
    window.activitiesChanged.connect(
      this.previousDesktopsChanged.bind(this)
    );
    window.outputChanged.connect(this.previousDesktopsChanged.bind(this));
    this.previousDesktopsChanged();
  }
  previousDesktopsChanged() {
    this.previousDesktops = this.previousDesktopsInternal;
    this.previousDesktopsInternal = this.desktopFactory.createDesktopsFromWindow(this.window);
  }
};

// src/controller/actions/shortcuts.ts
function pointAbove(window) {
  if (window.tile == null) {
    return null;
  }
  const geometry = window.frameGeometry;
  const coordOffset = 1 + window.tile.padding;
  const x = geometry.x + 1;
  const y = geometry.y - coordOffset;
  return new GPoint({
    x,
    y
  });
}
function pointBelow(window) {
  if (window.tile == null) {
    return null;
  }
  const geometry = window.frameGeometry;
  const coordOffset = 1 + geometry.height + window.tile.padding;
  const x = geometry.x + 1;
  const y = geometry.y + coordOffset;
  return new GPoint({
    x,
    y
  });
}
function pointLeft(window) {
  if (window.tile == null) {
    return null;
  }
  const geometry = window.frameGeometry;
  let coordOffset = 1 + window.tile.padding;
  let x = geometry.x - coordOffset;
  let y = geometry.y + 1;
  return new GPoint({
    x,
    y
  });
}
function pointRight(window) {
  if (window.tile == null) {
    return null;
  }
  const geometry = window.frameGeometry;
  let coordOffset = 1 + geometry.width + window.tile.padding;
  let x = geometry.x + coordOffset;
  let y = geometry.y + 1;
  return new GPoint({
    x,
    y
  });
}
function pointInDirection(window, direction) {
  switch (direction) {
    case 0 /* Above */:
      return pointAbove(window);
    case 2 /* Below */:
      return pointBelow(window);
    case 3 /* Left */:
      return pointLeft(window);
    case 1 /* Right */:
      return pointRight(window);
    default:
      return null;
  }
}
function gdirectionFromDirection(direction) {
  switch (direction) {
    case 0 /* Above */:
      return 1 /* Up */ | 4 /* Vertical */;
    case 2 /* Below */:
      return 4 /* Vertical */;
    case 3 /* Left */:
      return 0 /* None */;
    case 1 /* Right */:
      return 2 /* Right */;
  }
}
function engineName(engineType) {
  const engines = ["Binary Tree", "Half", "Three Column", "Monocle", "KWin"];
  return engines[engineType];
}
var ShortcutManager = class {
  constructor(ctrl) {
    this.ctrl = ctrl;
    this.logger = ctrl.logger;
    this.config = ctrl.config;
    let shortcuts = ctrl.qmlObjects.shortcuts;
    shortcuts.getRetileWindow().activated.connect(this.retileWindow.bind(this));
    shortcuts.getOpenSettings().activated.connect(this.openSettingsDialog.bind(this));
    shortcuts.getFocusAbove().activated.connect(this.focus.bind(this, 0 /* Above */));
    shortcuts.getFocusBelow().activated.connect(this.focus.bind(this, 2 /* Below */));
    shortcuts.getFocusLeft().activated.connect(this.focus.bind(this, 3 /* Left */));
    shortcuts.getFocusRight().activated.connect(this.focus.bind(this, 1 /* Right */));
    shortcuts.getInsertAbove().activated.connect(this.insert.bind(this, 0 /* Above */));
    shortcuts.getInsertBelow().activated.connect(this.insert.bind(this, 2 /* Below */));
    shortcuts.getInsertLeft().activated.connect(this.insert.bind(this, 3 /* Left */));
    shortcuts.getInsertRight().activated.connect(this.insert.bind(this, 1 /* Right */));
    shortcuts.getResizeAbove().activated.connect(this.resize.bind(this, 0 /* Above */));
    shortcuts.getResizeBelow().activated.connect(this.resize.bind(this, 2 /* Below */));
    shortcuts.getResizeLeft().activated.connect(this.resize.bind(this, 3 /* Left */));
    shortcuts.getResizeRight().activated.connect(this.resize.bind(this, 1 /* Right */));
    shortcuts.getCycleEngine().activated.connect(this.cycleEngine.bind(this));
    shortcuts.getSwitchBTree().activated.connect(this.setEngine.bind(this, 0 /* BTree */));
    shortcuts.getSwitchHalf().activated.connect(this.setEngine.bind(this, 1 /* Half */));
    shortcuts.getSwitchThreeColumn().activated.connect(
      this.setEngine.bind(this, 2 /* ThreeColumn */)
    );
    shortcuts.getSwitchMonocle().activated.connect(this.setEngine.bind(this, 3 /* Monocle */));
    shortcuts.getSwitchKwin().activated.connect(this.setEngine.bind(this, 4 /* Kwin */));
  }
  retileWindow() {
    const window = this.ctrl.workspace.activeWindow;
    if (window == null || !this.ctrl.windowExtensions.has(window)) {
      return;
    }
    if (this.ctrl.windowExtensions.get(window).isTiled) {
      this.ctrl.driverManager.untileWindow(window);
    } else {
      this.ctrl.driverManager.addWindow(window);
    }
    this.ctrl.driverManager.rebuildLayout();
  }
  openSettingsDialog() {
    const settings = this.ctrl.qmlObjects.settings;
    if (settings.isVisible()) {
      settings.hide();
    } else {
      const config = this.ctrl.driverManager.getEngineConfig(
        this.ctrl.desktopFactory.createDefaultDesktop()
      );
      settings.setSettings(config);
      settings.show();
    }
  }
  tileInDirection(window, point) {
    if (point == null) {
      return null;
    }
    return this.ctrl.workspace.tilingForScreen(window.output).bestTileForPosition(point.x, point.y);
  }
  focus(direction) {
    const window = this.ctrl.workspace.activeWindow;
    if (window == null) {
      return;
    }
    let tile = this.tileInDirection(
      window,
      pointInDirection(window, direction)
    );
    if (tile == null) {
      tile = this.ctrl.workspace.tilingForScreen(window.output).rootTile;
      while (tile.tiles.length == 1) {
        tile = tile.tiles[0];
      }
    }
    if (tile.windows.length == 0) {
      return;
    }
    let newWindow = tile.windows[0];
    this.logger.debug("Focusing", newWindow.resourceClass);
    this.ctrl.workspace.activeWindow = newWindow;
  }
  insert(direction) {
    const window = this.ctrl.workspace.activeWindow;
    if (window == null) {
      return;
    }
    const point = pointInDirection(window, direction);
    this.logger.debug("Moving", window.resourceClass);
    this.ctrl.driverManager.untileWindow(window);
    this.ctrl.driverManager.rebuildLayout(window.output);
    let tile = this.tileInDirection(window, point);
    if (tile == null) {
      tile = this.ctrl.workspace.tilingForScreen(window.output).rootTile;
      while (tile.tiles.length == 1) {
        tile = tile.tiles[0];
      }
    }
    this.ctrl.driverManager.putWindowInTile(
      window,
      tile,
      gdirectionFromDirection(direction)
    );
    this.ctrl.driverManager.rebuildLayout(window.output);
  }
  resize(direction) {
    const window = this.ctrl.workspace.activeWindow;
    if (window == null || window.tile == null) {
      return;
    }
    const tile = window.tile;
    const resizeAmount = this.config.resizeAmount;
    if (tile.parent == null) {
      return;
    }
    const siblingCount = tile.parent.tiles.length;
    const indexOfTile = tile.parent.tiles.indexOf(tile);
    this.logger.debug("Changing size of", tile.absoluteGeometry);
    switch (direction) {
      case 0 /* Above */:
        if (indexOfTile == 0) {
          tile.resizeByPixels(-resizeAmount, 8 /* BottomEdge */);
        } else {
          tile.resizeByPixels(-resizeAmount, 1 /* TopEdge */);
        }
        break;
      case 2 /* Below */:
        if (indexOfTile == siblingCount - 1) {
          tile.resizeByPixels(resizeAmount, 1 /* TopEdge */);
        } else {
          tile.resizeByPixels(resizeAmount, 8 /* BottomEdge */);
        }
        break;
      case 3 /* Left */:
        if (indexOfTile == 0) {
          tile.resizeByPixels(-resizeAmount, 4 /* RightEdge */);
        } else {
          tile.resizeByPixels(-resizeAmount, 2 /* LeftEdge */);
        }
        break;
      case 1 /* Right */:
        if (indexOfTile == siblingCount - 1) {
          tile.resizeByPixels(resizeAmount, 2 /* LeftEdge */);
        } else {
          tile.resizeByPixels(resizeAmount, 4 /* RightEdge */);
        }
        break;
    }
  }
  setEngine(engineType) {
    const desktop = this.ctrl.desktopFactory.createDefaultDesktop();
    const engineConfig = this.ctrl.driverManager.getEngineConfig(desktop);
    engineConfig.engineType = engineType;
    this.ctrl.qmlObjects.osd.show(engineName(engineType));
    this.ctrl.driverManager.setEngineConfig(desktop, engineConfig);
  }
  cycleEngine() {
    const desktop = this.ctrl.desktopFactory.createDefaultDesktop();
    const engineConfig = this.ctrl.driverManager.getEngineConfig(desktop);
    let engineType = engineConfig.engineType;
    engineType += 1;
    engineType %= 5 /* _loop */;
    engineConfig.engineType = engineType;
    this.ctrl.qmlObjects.osd.show(engineName(engineType));
    this.ctrl.driverManager.setEngineConfig(desktop, engineConfig);
  }
};

// src/controller/actions/windowhooks.ts
var WindowHooks = class {
  constructor(ctrl, window) {
    this.ctrl = ctrl;
    this.logger = ctrl.logger;
    this.window = window;
    this.extensions = ctrl.windowExtensions.get(window);
    window.desktopsChanged.connect(this.desktopChanged.bind(this));
    window.activitiesChanged.connect(this.desktopChanged.bind(this));
    window.outputChanged.connect(this.desktopChanged.bind(this));
    window.interactiveMoveResizeStepped.connect(
      this.interactiveMoveResizeStepped.bind(this)
    );
    window.tileChanged.connect(this.tileChanged.bind(this));
    window.fullScreenChanged.connect(this.fullscreenChanged.bind(this));
    window.minimizedChanged.connect(this.minimizedChanged.bind(this));
    window.maximizedAboutToChange.connect(this.maximizedChanged.bind(this));
  }
  desktopChanged() {
    this.logger.debug(
      "Desktops changed for window",
      this.window.resourceClass
    );
    const currentDesktops = this.ctrl.desktopFactory.createDesktopsFromWindow(this.window);
    const removeDesktops = [];
    const currentDesktopStrings = currentDesktops.map(
      (desktop) => desktop.toString()
    );
    for (const desktop of this.extensions.previousDesktops) {
      if (!currentDesktopStrings.includes(desktop.toString())) {
        removeDesktops.push(desktop);
      }
    }
    this.ctrl.driverManager.removeWindow(this.window, removeDesktops);
    const addDesktops = [];
    const previousDesktopStrings = this.extensions.previousDesktops.map(
      (desktop) => desktop.toString()
    );
    for (const desktop of currentDesktops) {
      if (!previousDesktopStrings.includes(desktop.toString())) {
        addDesktops.push(desktop);
      }
    }
    this.ctrl.driverManager.addWindow(this.window, addDesktops);
    if (!this.extensions.isTiled) {
      this.ctrl.driverManager.untileWindow(this.window, addDesktops);
    }
    this.ctrl.driverManager.rebuildLayout();
  }
  // have to use imrs and tilechanged
  // interactive mr handles moving out of tiles, tilechanged handles moving into tiles
  tileChanged(tile) {
    if (this.ctrl.driverManager.buildingLayout || tile == null) {
      return;
    }
    if (!this.extensions.isTiled && this.ctrl.managedTiles.has(tile)) {
      this.logger.debug(
        "Putting window",
        this.window.resourceClass,
        "in tile",
        tile.absoluteGeometry
      );
      const direction = new GRect(
        tile.absoluteGeometry
      ).directionFromPoint(this.ctrl.workspace.cursorPos);
      this.ctrl.driverManager.putWindowInTile(
        this.window,
        tile,
        direction
      );
      this.ctrl.driverManager.rebuildLayout(this.window.output);
    } else if (!this.ctrl.managedTiles.has(tile)) {
      this.logger.debug("Window", this.window.resourceClass, "moved into an unmanaged tile");
      const center = new GRect(tile.absoluteGeometryInScreen).center;
      let newTile = this.ctrl.workspace.tilingForScreen(this.window.output).bestTileForPosition(center.x, center.y);
      if (newTile == null) {
        newTile = this.ctrl.workspace.tilingForScreen(
          this.window.output
        ).rootTile;
      }
      if (this.extensions.isTiled) {
        this.ctrl.driverManager.untileWindow(this.window, [
          this.ctrl.desktopFactory.createDefaultDesktop()
        ]);
      }
      this.ctrl.driverManager.putWindowInTile(
        this.window,
        newTile,
        new GRect(newTile.absoluteGeometryInScreen).directionFromPoint(center)
      );
      this.ctrl.driverManager.rebuildLayout(this.window.output);
    }
  }
  // should be fine if i just leave this here without a timer
  interactiveMoveResizeStepped() {
    if (this.ctrl.driverManager.buildingLayout || this.ctrl.driverManager.resizingLayout || !this.extensions.isTiled) {
      return;
    }
    const inOldTile = this.window.tile != null && new GRect(this.window.tile.absoluteGeometry).contains(
      this.window.frameGeometry
    );
    const inUnmanagedTile = this.window.tile != null && !this.ctrl.managedTiles.has(this.window.tile);
    if (this.extensions.isTiled && !inUnmanagedTile && !inOldTile && !this.window.fullScreen && !this.extensions.maximized && !this.window.minimized) {
      this.logger.debug(
        "Window",
        this.window.resourceClass,
        "was moved out of a tile"
      );
      this.ctrl.driverManager.untileWindow(this.window, [
        this.ctrl.desktopFactory.createDefaultDesktop()
      ]);
      this.ctrl.driverManager.rebuildLayout(this.window.output);
    }
  }
  putWindowInBestTile() {
    if (this.extensions.lastTiledLocation != null) {
      let tile = this.ctrl.workspace.tilingForScreen(this.window.output).bestTileForPosition(
        this.extensions.lastTiledLocation.x,
        this.extensions.lastTiledLocation.y
      );
      if (tile == null) {
        tile = this.ctrl.workspace.tilingForScreen(
          this.window.output
        ).rootTile;
      }
      this.ctrl.driverManager.putWindowInTile(
        this.window,
        tile,
        new GRect(tile.absoluteGeometry).directionFromPoint(
          this.extensions.lastTiledLocation
        )
      );
    } else {
      this.ctrl.driverManager.addWindow(this.window);
    }
    this.ctrl.driverManager.rebuildLayout(this.window.output);
  }
  fullscreenChanged() {
    if (this.ctrl.driverManager.buildingLayout) {
      return;
    }
    this.logger.debug(
      "Fullscreen on client",
      this.window.resourceClass,
      "set to",
      this.window.fullScreen
    );
    if (this.window.fullScreen && this.extensions.isTiled) {
      this.ctrl.driverManager.untileWindow(this.window);
      this.ctrl.driverManager.rebuildLayout(this.window.output);
      this.extensions.wasTiled = true;
    } else if (!this.window.fullScreen && this.extensions.wasTiled && !this.extensions.isTiled && !this.window.minimized && !(this.extensions.maximized && this.extensions.isSingleMaximized)) {
      this.putWindowInBestTile();
    }
  }
  minimizedChanged() {
    this.logger.debug(
      "Minimized on client",
      this.window.resourceClass,
      "set to",
      this.window.minimized
    );
    if (this.window.minimized && this.extensions.isTiled) {
      this.ctrl.driverManager.untileWindow(this.window);
      this.ctrl.driverManager.rebuildLayout(this.window.output);
      this.extensions.wasTiled = true;
    } else if (!this.window.minimized && this.extensions.wasTiled && !this.extensions.isTiled && !this.window.fullScreen && !(this.extensions.maximized && this.extensions.isSingleMaximized)) {
      this.putWindowInBestTile();
    }
  }
  maximizedChanged(mode) {
    const maximized = mode == 3 /* MaximizeFull */;
    this.extensions.maximized = maximized;
    if (this.ctrl.driverManager.buildingLayout) {
      return;
    }
    if (this.extensions.isSingleMaximized) {
      return;
    }
    this.logger.debug(
      "Maximized on window",
      this.window.resourceClass,
      "set to",
      maximized
    );
    if (maximized && this.extensions.isTiled) {
      this.ctrl.driverManager.untileWindow(this.window);
      this.ctrl.driverManager.rebuildLayout(this.window.output);
      this.extensions.wasTiled = true;
    } else if (!maximized && this.extensions.wasTiled && !this.extensions.isTiled && !this.window.fullScreen && !this.window.minimized) {
      this.putWindowInBestTile();
    }
  }
};
var WindowHookManager = class {
  constructor(ctrl) {
    this.ctrl = ctrl;
    this.logger = this.ctrl.logger;
  }
  attachWindowHooks(window) {
    const extensions = this.ctrl.windowExtensions.get(window);
    if (extensions.clientHooks != null) {
      return;
    }
    this.logger.debug("Window", window.resourceClass, "hooked into script");
    extensions.clientHooks = new WindowHooks(this.ctrl, window);
  }
};

// src/controller/actions/settingsdialog.ts
var SettingsDialogManager = class {
  constructor(ctrl) {
    this.ctrl = ctrl;
    this.ctrl.qmlObjects.settings.saveSettings.connect(
      this.saveSettings.bind(this)
    );
    this.ctrl.qmlObjects.settings.removeSettings.connect(
      this.removeSettings.bind(this)
    );
  }
  saveSettings(settings, desktop) {
    this.ctrl.driverManager.setEngineConfig(
      this.ctrl.desktopFactory.createDesktopFromStrings(desktop),
      settings
    );
  }
  removeSettings(desktop) {
    const desktopObj = this.ctrl.desktopFactory.createDesktopFromStrings(desktop);
    this.ctrl.driverManager.removeEngineConfig(desktopObj);
    this.ctrl.dbusManager.removeSettings(desktopObj.toString());
  }
};

// src/controller/actions/basic.ts
var WorkspaceActions = class {
  constructor(ctrl) {
    this.logger = ctrl.logger;
    this.config = ctrl.config;
    this.ctrl = ctrl;
  }
  // done later after loading
  addHooks() {
    const workspace = this.ctrl.workspace;
    workspace.windowAdded.connect(this.windowAdded.bind(this));
    workspace.windowRemoved.connect(this.windowRemoved.bind(this));
    workspace.currentActivityChanged.connect(
      this.currentDesktopChange.bind(this)
    );
    workspace.currentDesktopChanged.connect(
      this.currentDesktopChange.bind(this)
    );
    workspace.windowActivated.connect(this.windowActivated.bind(this));
  }
  doTileWindow(c) {
    if (c.normalWindow && !((c.popupWindow || c.transient) && !this.config.tilePopups)) {
      if (c.fullScreen || c.minimized) {
        return false;
      }
      for (const s of this.config.filterProcess) {
        if (s.length > 0 && c.resourceClass.includes(s)) {
          return false;
        }
      }
      for (const s of this.config.filterCaption) {
        if (s.length > 0 && c.caption.includes(s)) {
          return false;
        }
      }
      return true;
    } else {
      return false;
    }
  }
  windowAdded(window) {
    this.ctrl.windowExtensions.set(
      window,
      new WindowExtensions(window, this.ctrl.desktopFactory)
    );
    this.ctrl.windowHookManager.attachWindowHooks(window);
    if (!this.doTileWindow(window)) {
      this.logger.debug("Not tiling window", window.resourceClass);
      return;
    }
    if (this.config.borders == 0 /* NoAll */) {
      window.noBorder = true;
    }
    this.logger.debug("Window", window.resourceClass, "added");
    this.ctrl.driverManager.addWindow(window);
    this.ctrl.driverManager.rebuildLayout();
  }
  windowRemoved(window) {
    this.logger.debug("Window", window.resourceClass, "removed");
    this.ctrl.driverManager.removeWindow(window);
    if (this.ctrl.windowExtensions.get(window).isTiled) {
      this.ctrl.driverManager.rebuildLayout();
    }
    this.ctrl.windowExtensions.delete(window);
  }
  currentDesktopChange() {
    this.ctrl.driverManager.buildingLayout = true;
    for (const window of this.ctrl.workspace.windows) {
      if (window.tile != null && window.activities.includes(
        this.ctrl.workspaceExtensions.lastActivity
      ) && window.desktops.includes(
        this.ctrl.workspaceExtensions.lastDesktop
      )) {
        const tile = window.tile;
        window.tile = null;
        window.frameGeometry = tile.absoluteGeometry;
        window.frameGeometry.width -= 2 * tile.padding;
        window.frameGeometry.height -= 2 * tile.padding;
        window.frameGeometry.x += tile.padding;
        window.frameGeometry.y += tile.padding;
      }
    }
    this.ctrl.driverManager.rebuildLayout();
  }
  windowActivated(window) {
    if (this.config.borders == 2 /* Selected */ && window != null) {
      window.noBorder = false;
      const lastActiveWindow = this.ctrl.workspaceExtensions.lastActiveWindow;
      if (lastActiveWindow != null && this.ctrl.windowExtensions.get(lastActiveWindow).isTiled) {
        lastActiveWindow.noBorder = true;
      }
    }
  }
};

// src/controller/index.ts
var Controller = class {
  constructor(qmlApi, qmlObjects) {
    this.windowExtensions = /* @__PURE__ */ new Map();
    this.managedTiles = /* @__PURE__ */ new Set();
    this.workspace = qmlApi.workspace;
    this.options = qmlApi.options;
    this.kwinApi = qmlApi.kwin;
    this.qmlObjects = qmlObjects;
    this.desktopFactory = new DesktopFactory(this.workspace);
    this.config = new Config(this.kwinApi);
    this.logger = new Log(this.config, this.qmlObjects.root);
    this.logger.info("Polonium started!");
    if (!this.config.debug) {
      this.logger.info(
        "Polonium debug is DISABLED! Enable it and restart KWin before sending logs!"
      );
    }
    this.logger.debug("Config is", JSON.stringify(this.config));
    this.workspaceExtensions = new WorkspaceExtensions(this.workspace);
    this.dbusManager = new DBusManager(this);
    this.driverManager = new DriverManager(this);
    this.shortcutManager = new ShortcutManager(this);
    this.windowHookManager = new WindowHookManager(this);
    this.settingsDialogManager = new SettingsDialogManager(this);
    this.workspaceActions = new WorkspaceActions(this);
    this.initTimer = qmlObjects.root.createTimer();
    this.initTimer.interval = this.config.timerDelay;
    this.initTimer.triggered.connect(this.initCallback.bind(this));
    this.initTimer.repeat = false;
  }
  init() {
    this.initTimer.start();
  }
  initCallback() {
    if (this.workspace.activities.length == 1 && this.workspace.activities[0] == "00000000-0000-0000-0000-000000000000") {
      this.logger.debug("Restarting init timer");
      this.initTimer.interval += this.config.timerDelay;
      this.initTimer.restart();
      return;
    }
    this.workspaceActions.addHooks();
    this.driverManager.init();
  }
};

// src/index.ts
function main(api, qmlObjects) {
  const ctrl = new Controller(api, qmlObjects);
  ctrl.init();
}
export {
  main
};
