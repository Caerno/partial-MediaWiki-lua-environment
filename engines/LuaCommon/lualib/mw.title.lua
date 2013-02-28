local title = {}
local php

local util = require 'libraryUtil'
local checkType = util.checkType
local checkTypeForIndex = util.checkTypeForIndex

local function checkNamespace( name, argIdx, arg )
	if type( arg ) == 'string' and tostring( tonumber( arg ) ) == arg then
		arg = tonumber( arg )
	end
	if type( arg ) == 'number' then
		arg = math.floor( arg + 0.5 )
		if not mw.site.namespaces[arg] then
			local msg = string.format( "bad argument #%d to '%s' (unrecognized namespace number '%s')",
				argIdx, name, arg
			)
			error( msg, 3 )
		end
	elseif type( arg ) == 'string' then
		local ns = mw.site.namespaces[arg]
		if not ns then
			local msg = string.format( "bad argument #%d to '%s' (unrecognized namespace name '%s')",
				argIdx, name, arg
			)
			error( msg, 3 )
		end
		arg = ns.id
	else
		local msg = string.format( "bad argument #%d to '%s' (string or number expected, got %s)",
			argIdx, name, type( arg )
		)
		error( msg, 3 )
	end
	return arg
end


local function lt( a, b )
	if a.interwiki ~= b.interwiki then
		return a.interwiki < b.interwiki
	end
	if a.namespace ~= b.namespace then
		return a.namespace < b.namespace
	end
	return a.text < b.text
end

local function makeTitleObject( data )
	if not data then
		return nil
	end

	local obj = {}
	local checkSelf = util.makeCheckSelfFunction( 'mw.title', 'title', obj, 'title object' );
	local ns = mw.site.namespaces[data.namespace]

	data.isContentPage = ns.isContent
	data.isExternal = data.interwiki ~= ''
	data.isSpecialPage = data.namespace == mw.site.namespaces.Special.id
	data.isTalkPage = ns.isTalk
	data.exists = data.id ~= 0
	data.subjectNsText = ns.subject.name
	data.canTalk = ns.talk ~= nil

	data.prefixedText = data.text
	if data.nsText ~= '' then
		data.prefixedText = data.nsText .. ':' .. data.prefixedText
	end
	if data.interwiki ~= '' then
		data.prefixedText = data.interwiki .. ':' .. data.prefixedText
	end

	local firstSlash, lastSlash
	if ns.hasSubpages then
		firstSlash, lastSlash = string.match( data.text, '^[^/]*().*()/[^/]*$' )
	end
	if firstSlash then
		data.isSubpage = true
		data.rootText = string.sub( data.text, 1, firstSlash - 1 )
		data.baseText = string.sub( data.text, 1, lastSlash - 1 )
		data.subpageText = string.sub( data.text, lastSlash + 1 )
	else
		data.isSubpage = false
		data.rootText = data.text
		data.baseText = data.text
		data.subpageText = data.text
	end

	function data:inNamespace( ns )
		checkSelf( self, 'inNamespace' )
		ns = checkNamespace( 'inNamespace', 1, ns )
		return ns == self.namespace
	end

	function data:inNamespaces( ... )
		checkSelf( self, 'inNamespaces' )
		for i = 1, select( '#', ... ) do
			local ns = checkNamespace( 'inNamespaces', i, select( i, ... ) )
			if ns == self.namespace then
				return true
			end
		end
		return false
	end

	function data:hasSubjectNamespace( ns )
		checkSelf( self, 'hasSubjectNamespace' )
		ns = checkNamespace( 'hasSubjectNamespace', 1, ns )
		return ns == mw.site.namespaces[self.namespace].subject.id
	end

	function data:isSubpageOf( title )
		checkSelf( self, 'isSubpageOf' )
		checkType( 'isSubpageOf', 1, title, 'table' )
		return self.interwiki == title.interwiki and
			self.namespace == title.namespace and
			title.text .. '/' == string.sub( self.text, 1, #title.text + 1 )
	end

	function data:subPageTitle( text )
		checkSelf( self, 'subpageTitle' )
		checkType( 'subpageTitle', 1, text, 'string' )
		return title.makeTitle( data.namespace, data.text .. '/' .. text )
	end

	function data:partialUrl()
		checkSelf( self, 'partialUrl' )
		return data.thePartialUrl
	end

	function data:fullUrl( query, proto )
		checkSelf( self, 'fullUrl' )
		return php.getUrl( self.fullText, 'fullUrl', query, proto )
	end

	function data:localUrl( query )
		checkSelf( self, 'localUrl' )
		return php.getUrl( self.fullText, 'localUrl', query )
	end

	function data:canonicalUrl( query )
		checkSelf( self, 'canonicalUrl' )
		return php.getUrl( self.fullText, 'canonicalUrl', query )
	end

	return setmetatable( obj, {
		__eq = title.equals,
		__lt = lt,
		__index = function ( t, k )
			if k == 'fullText' then
				if data.fragment ~= '' then
					return data.prefixedText .. '#' .. data.fragment
				else
					return data.prefixedText
				end
			end

			if k == 'rootPageTitle' then
				return title.makeTitle( data.namespace, data.rootText )
			end
			if k == 'basePageTitle' then
				return title.makeTitle( data.namespace, data.baseText )
			end
			if k == 'talkPageTitle' then
				local ns = mw.site.namespaces[data.namespace].talk
				if not ns then
					return nil
				end
				if ns.id == data.namespace then
					return obj
				end
				return title.makeTitle( ns.id, data.text )
			end
			if k == 'subjectPageTitle' then
				local ns = mw.site.namespaces[data.namespace].subject
				if ns.id == data.namespace then
					return obj
				end
				return title.makeTitle( ns.id, data.text )
			end

			return data[k]
		end,
		__newindex = function ( t, k, v )
			if k == 'fragment' then
				checkTypeForIndex( k, v, 'string' )
				data[k] = v
			elseif data[k] then
				error( "index '" .. k .. "' is read only", 2 )
			else
				rawset( t, k, v )
			end
		end,
		__tostring = function ( t )
			return t.prefixedText
		end
	} )
end

function title.setupInterface( options )
	-- Boilerplate
	title.setupInterface = nil
	php = mw_interface
	mw_interface = nil

	-- Set current title
	title.getCurrentTitle = function ()
		return makeTitleObject( options.thisTitle )
	end

	-- Register this library in the "mw" global
	mw = mw or {}
	mw.title = title

	package.loaded['mw.title'] = title
end

function title.new( text_or_id, defaultNamespace )
	return makeTitleObject( php.newTitle( text_or_id, defaultNamespace ) )
end

function title.makeTitle( ns, title, fragment, interwiki )
	return makeTitleObject( php.makeTitle( ns, title, fragment, interwiki ) )
end

function title.equals( a, b )
	return a.interwiki == b.interwiki and
		a.namespace == b.namespace and
		a.text == b.text
end

function title.compare( a, b )
	if a.interwiki ~= b.interwiki then
		return a.interwiki < b.interwiki and -1 or 1
	end
	if a.namespace ~= b.namespace then
		return a.namespace < b.namespace and -1 or 1
	end
	if a.text ~= b.text then
		return a.text < b.text and -1 or 1
	end
	return 0
end

return title