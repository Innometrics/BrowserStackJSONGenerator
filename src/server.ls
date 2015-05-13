require! lson
require! fs
require! request
require! mkdirp
{unique, maximum-by, is-it-NaN, find, sort-with, first, last, reverse, unique-by, filter, values, concat} = require 'prelude-ls'

credentials = lson.parse fs.readFileSync "./settings/credentials.lson" "utf8"
directives = lson.parse fs.readFileSync "./settings/directives.lson" "utf8"

conf = auth:
    user: credentials.username
    pass: credentials.pwd

#getting the raw JSON from browserstack
request "https://www.browserstack.com/automate/browsers.json", conf, (error, response, body) ->
  if (!error && response.statusCode == 200)
    browsers = JSON.parse body
    fileGenerator browserSelecter (treeBuilder browsers)
    console.log "Files are generated."

fileGenerator = (tree) ->
  mkdirp "files"
  for own let os, browsers of tree
    tempArr = []
    for own let key, browsersArr of browsers
      tempArr := tempArr.concat browsersArr
    # split the browser in different files
    fs.writeFile (\files/ + (os.replace(\., \-) + \.json) - ' '), (JSON.stringify tempArr, null, 2)
    tree[os] = tempArr

  # One massive file wit all browsers
  fs.writeFile \files/all.json, (JSON.stringify (concat (values tree)), null, 2)

  tree

browserSelecter = (tree) ->
  tempArr = []
  for own let os, browsersTree of tree
    # we first remove the browser we don't want
    tempArr = browserExcluder os, browsersTree
    # then we keep only the few we want
    tree[os] = browserIncluder os, tempArr
  tree

# keep only the browsers described in directives
browserIncluder = (os, browsersTree) ->
  for own let browserName, browsersArray of browsersTree
    tempArr = []
    directive = (directives.only[os] || directives.only.os)?[browserName]

    unless directive
      return

    # Check if a version number is described in directives
    versions = filter ((a)-> !is-it-NaN +a), directive

    for browser in browsersArray
      if browser.browser_version in versions
        tempArr.push browser

    browsersArray = (sort-with coercetor, browsersArray)

    if ("MIN" in directive)
      tempArr.push first browsersArray

    if ("MAX" in directive)
      tempArr.push last browsersArray

    #if a MIN == MAX or forced version == (MIN || MAX)
    browsersTree[browserName] = unique tempArr
  browsersTree

# removes the browsers described in directives
browserExcluder = (os, browsersTree) ->
  for own let browserName, browsersArray of browsersTree
    tempArr = []
    directive = (directives.remove[os] || directives.remove.os)

    # if os==browserName -> mobile browser
    unless os == browserName or directive?[browserName]
      return

    for browser in browsersArray
      keep = true
      for dir in directive
        for own let key of dir
          if browser[key] == dir[key]
            keep := false
      if keep
        tempArr.push browser
    browsersTree[browserName] = tempArr

  browsersTree

#splits the browsers descriptions in different objects depending on directives.splitOSInVersion
treeBuilder = (browsers) ->
  tree = {}
  [browsersDispatcherByOS .., tree for browsers]
  tree

# typeof tree == {}
# typeof tree.os == {}
# typeof tree.os.browsers == []
browsersDispatcherByOS = (browser, tree) ->
  # if browsers versions have precedence over OS
  if browser.os in directives.splitOSInVersion
    browserDispatcher browser, \os_version, \browser, tree
  else
    browserDispatcher browser, \os, \os, tree

browserDispatcher = (browser, osStr, browserStr, tree) ->
  brow = browser[browserStr]
  os = browser[osStr]

  tree[os] ?= {}
  tree[os][brow] ?= []

  tree[os][brow].push browser

coercetor = (x, y) ->
  | +x.browser_version < +y.browser_version => -1
  | +x.browser_version > +y.browser_version => 1
  | _ => 0
