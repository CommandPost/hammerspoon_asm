@import Cocoa ;
@import LuaSkin ;

static const char * const USERDATA_TAG = "hs.doc" ; // we're using it as a module tag for console messages
static int refTable     = LUA_NOREF;
static int refTriggerFn = LUA_NOREF ;

static NSMutableDictionary *registeredFilesDictionary ;
static NSMutableDictionary *documentationTree ;

// #define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))
// #define get_structFromUserdata(objType, L, idx, tag) ((objType *)luaL_checkudata(L, idx, tag))
// #define get_cfobjectFromUserdata(objType, L, idx, tag) *((objType *)luaL_checkudata(L, idx, tag))

#pragma mark - Support Functions and Classes

// NSOrderedAscending
// NSOrderedDescending
// NSOrderedSame
NSInteger docSortFunction(NSString *a, NSString *b, __unused void *context) {
    LuaSkin *skin = [LuaSkin shared] ;
    NSError *error = nil ;
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"^_\\d([\\d_])*"
                                                                            options:NSRegularExpressionUseUnicodeWordBoundaries
                                                                              error:&error] ;
    if (!error) {
        NSTextCheckingResult *aMatch = [parser firstMatchInString:a options:0 range:NSMakeRange(0, a.length)] ;
        NSTextCheckingResult *bMatch = [parser firstMatchInString:b options:0 range:NSMakeRange(0, b.length)] ;
        if (aMatch.range.length != 0 && bMatch.range.length != 0) {
            NSString *aTag = [a substringWithRange:aMatch.range] ;
            NSString *bTag = [b substringWithRange:bMatch.range] ;
            parser = [NSRegularExpression regularExpressionWithPattern:@"\\d+"
                                                               options:NSRegularExpressionUseUnicodeWordBoundaries
                                                                 error:&error] ;
            if (!error) {
                NSArray *aNumericParts = [parser matchesInString:aTag options:0 range:NSMakeRange(0, aTag.length)] ;
                NSArray *bNumericParts = [parser matchesInString:bTag options:0 range:NSMakeRange(0, bTag.length)] ;

                NSUInteger minCount = (aNumericParts.count < bNumericParts.count) ? aNumericParts.count : bNumericParts.count ;
                NSNumberFormatter *f = [[NSNumberFormatter alloc] init] ;
                f.numberStyle = NSNumberFormatterNoStyle ;
                for (NSUInteger i = 0 ; i < minCount ; i++) {
                    NSTextCheckingResult *aPartMatch = aNumericParts[i] ;
                    NSTextCheckingResult *bPartMatch = bNumericParts[i] ;
                    NSNumber *aNumber = [f numberFromString:[a substringWithRange:aPartMatch.range]] ;
                    NSNumber *bNumber = [f numberFromString:[b substringWithRange:bPartMatch.range]] ;
                    NSComparisonResult test = [aNumber compare:bNumber] ;
                    if (test != NSOrderedSame) return test ;
                }
                return (aNumericParts.count < bNumericParts.count) ? NSOrderedAscending
                                                                   : ((aNumericParts.count > bNumericParts.count) ? NSOrderedDescending : NSOrderedSame) ;
            } else {
                [skin logError:[NSString stringWithFormat:@"%s.docSortFunction - error initializing 2nd regex: %@", USERDATA_TAG, error.localizedDescription]] ;
            }
        }
    } else {
        [skin logError:[NSString stringWithFormat:@"%s.docSortFunction - error initializing regex: %@", USERDATA_TAG, error.localizedDescription]] ;
    }
    return [a caseInsensitiveCompare:b] ;
}

static int internal_registerTriggerFunction(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TFUNCTION, LS_TBREAK] ;

    if (refTriggerFn != LUA_NOREF && refTriggerFn != LUA_REFNIL) {
        refTriggerFn = [skin luaUnref:refTable ref:refTriggerFn] ;
    }
    lua_pushvalue(L, 1) ;
    refTriggerFn = [skin luaRef:refTable] ;
    return 0 ;
}

#pragma mark - Module Functions

static int doc_arrayOfChildren(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING | LS_TNIL | LS_TOPTIONAL, LS_TBREAK] ;
    NSString *identifier = @"" ;
    if (lua_gettop(L) == 1 && lua_type(L, 1) == LUA_TSTRING) identifier = [skin toNSObjectAtIndex:1] ;

    lua_newtable(L) ;
    NSError *error = nil ;
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"[^.]+"
                                                                            options:NSRegularExpressionUseUnicodeWordBoundaries
                                                                              error:&error] ;
    if (!error) {
        __block NSMutableDictionary *pos = documentationTree ;
        [parser enumerateMatchesInString:identifier
                                 options:0
                                   range:NSMakeRange(0, identifier.length)
                              usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags __unused flags, BOOL *stop) {
            NSString *part = [identifier substringWithRange:match.range] ;
            if (pos[part]) {
                pos = pos[part] ;
            } else {
                pos = nil ;
                *stop = YES ;
            }
        }] ;

        if (pos) {
            for (NSString *entry in [(NSDictionary *)pos allKeys]) {
                if (!([entry hasPrefix:@"__"] && [entry hasSuffix:@"__"])) {
                    [skin pushNSObject:entry] ;
                    lua_rawseti(L, -2, luaL_len(L, -2) + 1) ;
                }
            }
        }
    } else {
        [skin logError:[NSString stringWithFormat:@"%s.help - error initializing regex: %@", USERDATA_TAG, error.localizedDescription]] ;
    }
    return 1 ;
}

static NSMutableArray *arrayOf_hamster(NSMutableDictionary *root) {
    NSMutableArray *answers = [[NSMutableArray alloc] init] ;
    if (root[@"__type__"] && [(NSString *)root[@"__type__"] isEqualToString:@"module"]) {
        NSMutableDictionary *json = root[@"__json__"] ;
        if (json) [answers addObject:json] ;
    }

    for (NSMutableDictionary *node in [root allValues]) {
        if ([node isKindOfClass:[NSDictionary class]]) {
            if (node[@"__json__"]) [answers addObjectsFromArray:arrayOf_hamster(node)] ;
        }
    }
    return answers ;
}

static int doc_arrayOfModuleJsonSegments(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING, LS_TBREAK] ;
    NSString *target = [skin toNSObjectAtIndex:1] ;

    NSMutableDictionary *root = documentationTree[target] ;
    if (root) {
        [skin pushNSObject:arrayOf_hamster(root)] ;
    } else {
        lua_pushnil(L) ;
    }
    return 1 ;
}

// documented in init.lua
static int doc_help(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING | LS_TNIL | LS_TOPTIONAL, LS_TBREAK] ;
    NSString *identifier = @"" ;
    if (lua_gettop(L) == 1 && lua_type(L, 1) == LUA_TSTRING) identifier = [skin toNSObjectAtIndex:1] ;

    NSMutableString *result = [[NSMutableString alloc] init] ;

    NSError *error = nil ;
    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"[^.]+"
                                                                            options:NSRegularExpressionUseUnicodeWordBoundaries
                                                                              error:&error] ;
    if (!error) {
        __block NSMutableDictionary *pos = documentationTree ;
        [parser enumerateMatchesInString:identifier
                                 options:0
                                   range:NSMakeRange(0, identifier.length)
                              usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags __unused flags, BOOL *stop) {
            NSString *part = [identifier substringWithRange:match.range] ;
            if (pos[part]) {
                pos = pos[part] ;
            } else {
                pos = nil ;
                *stop = YES ;
            }
        }] ;

        if (pos) {
            result = [[NSMutableString alloc] init] ;

            if ([(NSString *)pos[@"__type__"] isEqualToString:@"root"]) {
                [result appendString:@"[modules]\n"] ;
                NSMutableArray *children = [[(NSDictionary *)pos allKeys] mutableCopy] ;
                [children sortUsingSelector:@selector(caseInsensitiveCompare:)] ;
                for (NSString *entry in children) {
                    if (!([entry hasPrefix:@"__"] && [entry hasSuffix:@"__"])) {
                        [result appendFormat:@"%@\n", entry] ;
                    }
                }
            } else if ([(NSString *)pos[@"__type__"] isEqualToString:@"spoons"]) {
                [result appendString:@"[spoons]\n"] ;
                NSMutableArray *children = [[(NSDictionary *)pos allKeys] mutableCopy] ;
                [children sortUsingSelector:@selector(caseInsensitiveCompare:)] ;
                for (NSString *entry in children) {
                    if (!([entry hasPrefix:@"__"] && [entry hasSuffix:@"__"])) {
                        [result appendFormat:@"%@\n", entry] ;
                    }
                }
            } else if (pos[@"__json__"] && !pos[@"__json__"][@"items"]) {
                [result appendFormat:@"%@: %@\n\n%@\n",
                    pos[@"__json__"][@"type"],
                    (pos[@"__json__"][@"signature"] ? pos[@"__json__"][@"signature"] : pos[@"__json__"][@"def"]),
                    pos[@"__json__"][@"doc"]
                ] ;
            } else {
                if (pos[@"__json__"]) {
                    [result appendFormat:@"%@", pos[@"__json__"][@"doc"]] ;
                } else {
                    [result appendString:@"** DOCUMENTATION MISSING **"] ;
                }
                NSMutableString *submodules = [[NSMutableString alloc] init] ;
                NSMutableString *items      = [[NSMutableString alloc] init] ;
                NSMutableArray *children = [[(NSDictionary *)pos allKeys] mutableCopy] ;
                [children sortUsingFunction:docSortFunction context:NULL] ;
                [children enumerateObjectsUsingBlock:^(NSString *entry, __unused NSUInteger idx, __unused BOOL *stop) {
                    if (!([entry hasPrefix:@"__"] && [entry hasSuffix:@"__"])) {
                        if (!pos[entry][@"__json__"] || !pos[entry][@"__json__"][@"type"] || [(NSString *)pos[entry][@"__json__"][@"type"] isEqualToString:@"Module"]) {
                            [submodules appendFormat:@"%@\n", entry] ;
                        } else {
                            NSString *itemSignature = pos[entry][@"__json__"][@"signature"] ? pos[entry][@"__json__"][@"signature"] : pos[entry][@"__json__"][@"def"] ;
                            [items appendFormat:@"%@\n", itemSignature] ;
                        }
                    }
                }] ;
                [result appendFormat:@"\n\n[submodules]\n%@\n[items]\n%@\n", submodules, items] ;
            }
        }
    } else {
        [skin logError:[NSString stringWithFormat:@"%s.help - error initializing regex: %@", USERDATA_TAG, error.localizedDescription]] ;
    }

    [skin pushNSObject:result] ;
    return 1 ;

//     lua_getglobal(L, "print") ;
//     [skin pushNSObject:result] ;
//     lua_call(L, 1, 0) ;
//     return 0 ;
}

/// hs.doc.registerJSONFile(jsonfile, [isSpoon]) -> status[, message]
/// Function
/// Register a JSON file for inclusion when Hammerspoon generates internal documentation.
///
/// Parameters:
///  * jsonfile - A string containing the location of a JSON file
///  * isSpoon  - an optional boolean, default false, specifying that the documentation should be added to the `spoons` sub heading in the documentation hierarchy.
///
/// Returns:
///  * status - Boolean flag indicating if the file was registered or not.  If the file was not registered, then a message indicating the error is also returned.
static int doc_registerJSONFile(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING, LS_TBOOLEAN | LS_TOPTIONAL, LS_TBREAK] ;
    NSString *path   = [skin toNSObjectAtIndex:1] ;
    BOOL     isSpoon = (lua_gettop(L) > 1) ? (BOOL)lua_toboolean(L, 2) : NO ;

    if (registeredFilesDictionary[path]) {
        lua_pushboolean(L, NO) ;
        [skin pushNSObject:[NSString stringWithFormat:@"File '%@' already registered", path]] ;
        return 2 ;
    }

    NSError *error = nil ;
    NSData *rawFile = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error] ;
    if (!rawFile || error) {
        lua_pushboolean(L, NO) ;
        [skin pushNSObject:[NSString stringWithFormat:@"Unable to open '%@' (%@)", path, error.localizedDescription]] ;
        return 2 ;
    }

    id obj = [NSJSONSerialization JSONObjectWithData:rawFile options:NSJSONReadingAllowFragments error:&error] ;
    if (error) {
        lua_pushboolean(L, NO) ;
        [skin pushNSObject:error.localizedDescription] ;
        return 2 ;
    } else if (!obj) {
        lua_pushboolean(L, NO) ;
        [skin pushNSObject:@"json input returned nil"] ;
        return 2 ;
    }

    registeredFilesDictionary[path] = [[NSMutableDictionary alloc] init] ;
    registeredFilesDictionary[path][@"json"]  = obj ;
    registeredFilesDictionary[path][@"spoon"] = @(isSpoon) ;

    if (isSpoon && !documentationTree[@"spoon"]) {
        documentationTree[@"spoon"] = [@{ @"__type__" : @"spoons" } mutableCopy] ;
    }

    NSMutableDictionary *root = isSpoon ? documentationTree[@"spoon"] : documentationTree ;

    if (![(NSObject *)obj isKindOfClass:[NSArray class]]) {
        lua_pushboolean(L, NO) ;
        [skin pushNSObject:@"malformed documentation file -- proper format requires an array of entries"] ;
        return 2 ;
    }

    NSRegularExpression *parser = [NSRegularExpression regularExpressionWithPattern:@"[\\w_]+"
                                                                            options:NSRegularExpressionUseUnicodeWordBoundaries
                                                                              error:&error] ;
    if (!error) {
        [(NSArray *)obj enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger idx, __unused BOOL *stop) {
            __block NSMutableDictionary *pos = root ;

            if (![entry isKindOfClass:[NSDictionary class]] || !entry[@"name"]) {
                [skin logError:[NSString stringWithFormat:@"%s.registerJSONFile - malformed entry -- expected module dictionary with 'name' key at index %lu in %@; skipping", USERDATA_TAG, idx + 1, path]] ;
            } else {
                NSString *entryName = entry[@"name"] ;
                [parser enumerateMatchesInString:entryName
                                         options:0
                                           range:NSMakeRange(0, entryName.length)
                                      usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags __unused flags, __unused BOOL *stop2) {
                    NSString *part = [entryName substringWithRange:match.range] ;
                    if (!pos[part]) pos[part] = [@{ @"__type__" : @"placeholder" } mutableCopy] ;
                    pos = pos[part] ;
                }] ;

                if (pos[@"__json__"]) {
                    // FIXME: Duplicate Handling
                    //    In theory additions or changes to the module could be defined elsewhere. Bad style, so log anyways, and we'll
                    //    decide how to officially handle it if it becomes normal as opposed to an "in-development" shortcut. For now,
                    //    assume since coredocs are loaded first, that this is an in-progress update that should overwrite the original.
                    [skin logWarn:[NSString stringWithFormat:@"%s.registerJSONFile - duplicate module entry for %@ (%@)", USERDATA_TAG, entryName, entry[@"desc"]]] ;
                }
                pos[@"__json__"] = entry ;
                pos[@"__type__"] = @"module" ; // this is more than a placeholder now

                if (entry[@"items"]) {
                    NSArray *itemsAttached = entry[@"items"] ;
                    if ([itemsAttached isKindOfClass:[NSArray class]]) {
                        [(NSArray *)entry[@"items"] enumerateObjectsUsingBlock:^(NSDictionary *itemEntry, NSUInteger idx2, __unused BOOL *stop2) {

                        if (![itemEntry isKindOfClass:[NSDictionary class]] || !itemEntry[@"name"]) {
                            [skin logError:[NSString stringWithFormat:@"%s.registerJSONFile - malformed entry -- expected item dictionary with 'name' key for %@ at index %lu in %@; skipping", USERDATA_TAG, entryName, idx2 + 1, path]] ;
                        } else {
                            NSString *itemName = itemEntry[@"name"] ;
                            NSTextCheckingResult *match = [parser firstMatchInString:itemName options:0 range:NSMakeRange(0, itemName.length)] ;
                            if (match.range.location != NSNotFound) {
                                NSString *part = [itemName substringWithRange:match.range] ;
                                if (pos[part]) {
                                    // FIXME: Duplicate Handling
                                    //     See above for current behavior and reasoning
                                    [skin logWarn:[NSString stringWithFormat:@"%s.registerJSONFile - duplicate item entry of %@ (%@) for %@", USERDATA_TAG, itemName, entry[@"def"], entryName]] ;
                                }
                                NSMutableDictionary *itemDict = [@{ @"__type__" : @"entry" } mutableCopy] ;
                                itemDict[@"__json__"] = itemEntry ;
                                pos[part] = itemDict ;
                            } else {
                                [skin logError:[NSString stringWithFormat:@"%s.registerJSONFile - malformed entry -- item name (%@) invalid for %@ at index %lu in %@; skipping", USERDATA_TAG, itemName, entryName, idx2 + 1, path]] ;
                            }
                        }
                    }] ;
                    } else {
                        [skin logError:[NSString stringWithFormat:@"%s.registerJSONFile - malformed entry -- expected array or nil in 'items' key for %@ at index %lu in %@; skipping", USERDATA_TAG, entryName, idx + 1, path]] ;
                    }
                } // no items at all is ok, we only log when items isn't an array
            }
        }] ;
    } else {
        [skin logError:[NSString stringWithFormat:@"%s.registerJSONFile - error initializing regex: %@", USERDATA_TAG, error.localizedDescription]] ;
    }

    [skin pushLuaRef:refTable ref:refTriggerFn] ;
    lua_call(L, 0, 0) ;

    lua_pushboolean(L, YES) ;
    return 1 ;
}

/// hs.doc.unregisterJSONFile(jsonfile) -> status[, message]
/// Function
/// Remove a JSON file from the list of registered files.
///
/// Parameters:
///  * jsonfile - A string containing the location of a JSON file
///
/// Returns:
///  * status - Boolean flag indicating if the file was unregistered or not.  If the file was not unregistered, then a message indicating the error is also returned.
static int doc_unregisterJSONFile(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING, LS_TBREAK] ;
    NSString *path   = [skin toNSObjectAtIndex:1] ;

    if (!registeredFilesDictionary[path]) {
        lua_pushboolean(L, NO) ;
        [skin pushNSObject:[NSString stringWithFormat:@"File '%@' was not registered", path]] ;
        return 2 ;
    }

    // TODO: magic happens here

    registeredFilesDictionary[path] = nil ;
    lua_pushboolean(L, YES) ;
    return 1 ;
}

// documented in init.lua
static int doc_registeredFiles(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;

    NSMutableArray *sortedPaths = [[registeredFilesDictionary allKeys] mutableCopy] ;
    [sortedPaths sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)] ;
    [skin pushNSObject:sortedPaths] ;
    return 1 ;
}

// // Not actually used by anything outside of this module, but if we find out otherwise, it can easily
// // be re-added by uncommenting this and the entry in moduleLib below
// //
// /// hs.doc.validateJSONFile(jsonfile) -> status, message|table
// /// Function
// /// Validate a JSON file potential inclusion in the Hammerspoon internal documentation.
// ///
// /// Parameters:
// ///  * jsonfile - A string containing the location of a JSON file
// ///
// /// Returns:
// ///  * status - Boolean flag indicating if the file was validated or not.
// ///  * message|table - If the file did not contain valid JSON data, then a message indicating the error is returned; otherwise the parsed JSON data is returned as a table.
// static int doc_validateJSONFile(lua_State *L) {
//     LuaSkin *skin = [LuaSkin shared] ;
//     [skin checkArgs:LS_TSTRING, LS_TBREAK] ;
//     NSString *path   = [skin toNSObjectAtIndex:1] ;
//
//     NSError *error ;
//     NSData *rawFile = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error] ;
//     if (!rawFile || error) {
//         lua_pushboolean(L, NO) ;
//         [skin pushNSObject:[NSString stringWithFormat:@"Unable to open '%@' (%@)", path, error.localizedDescription]] ;
//         return 2 ;
//     }
//
//     id obj = [NSJSONSerialization JSONObjectWithData:fileData options:NSJSONReadingAllowFragments error:&error] ;
//     if (error) {
//         lua_pushboolean(L, NO) ;
//         [skin pushNSObject:error.localizedDescription] ;
//     } else if (obj) {
//         lua_pushboolean(L, YES) ;
//         [skin pushNSObject:obj] ;
//     } else {
//         lua_pushboolean(L, NO) ;
//         [skin pushNSObject:@"json input returned nil"] ;
//     }
//     return 2 ;
// }

#pragma mark - Debugging Tools

// Shouldn't generally be necessary, so we hide them in the metatable to prevent accidental access
// They are *really* slow because invoking them replicates all of the json data collected thus far
// in lua all at once.

static int debug_registeredFilesDictionary(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TBREAK] ;
    [skin pushNSObject:registeredFilesDictionary] ;
    return 1 ;
}

static int debug_documentationTree(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TBREAK] ;
    [skin pushNSObject:documentationTree] ;
    return 1 ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int meta_gc(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin shared] ;
    refTriggerFn = [skin luaUnref:refTable ref:refTriggerFn] ;

    // probably overkill, but lets just be official about it
    [registeredFilesDictionary removeAllObjects] ;
    registeredFilesDictionary = nil ;
    [documentationTree removeAllObjects] ;
    documentationTree = nil ;
    return 0 ;
}

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {"help",               doc_help},
    {"registerJSONFile",   doc_registerJSONFile},
    {"registeredFiles",    doc_registeredFiles},
    {"unregisterJSONFile", doc_unregisterJSONFile},
//     {"validateJSONFile",   doc_validateJSONFile},
    {"_children",          doc_arrayOfChildren},
    {"_moduleJson",        doc_arrayOfModuleJsonSegments},

    {NULL, NULL}
};

// Metatable for module, if needed
static const luaL_Reg module_metaLib[] = {
    {"_registeredFilesDictionary", debug_registeredFilesDictionary},
    {"_documentationTree",         debug_documentationTree},
    {"_registerTriggerFunction",   internal_registerTriggerFunction},
    {"__gc",                       meta_gc},
    {NULL,   NULL}
};

int luaopen_hs_doc_internal(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin shared] ;
    refTable = [skin registerLibrary:moduleLib metaFunctions:module_metaLib] ;

    registeredFilesDictionary = [[NSMutableDictionary alloc] init] ;
    documentationTree         = [@{ @"__type__" : @"root" } mutableCopy] ;


    return 1;
}
