Jxon_Load(src, args*)
{
	static is_v2 := A_AhkVersion >= "2", q := Chr(34)

	i := 0, strings := []
	while i := InStr(src, q,, i+1)
	{
		static Replace := Func(is_v2 ? "StrReplace" : "RegExReplace")
		static bash := is_v2 ? "\" : "\\"

		j := i
		while j := InStr(src, q,, j+1)
		{
			str := %Replace%(SubStr(src, i+1, j-i-1), bash . bash, "\u005C")
			static end := is_v2 ? -1 : 0
			if (SubStr(str, end) != "\")
				break
		}
		if !j
			throw Exception("Missing close quote(s).", -1)

		src := SubStr(src, 1, i) . SubStr(src, j+1)

		  str := %Replace%(str, bash . "/",  "/")
		, str := %Replace%(str, bash .   q,    q)
		, str := %Replace%(str, bash . "b", "`b")
		, str := %Replace%(str, bash . "f", "`f")
		, str := %Replace%(str, bash . "n", "`n")
		, str := %Replace%(str, bash . "r", "`r")
		, str := %Replace%(str, bash . "t", "`t")

		j := 0
		while j := InStr(str, "\",, j+1) ; parse remaining chars with preceding "\"
		{
			if (SubStr(str, j+1, 1) != "u")
				throw Exception("Invalid escape sequence.", -1, SubStr(str, j, 2))

			; \uXXXX - JSON unicode escape sequence
			ord := Abs("0x" . SubStr(str, j+2, 4)) ; XXXX
			if (A_IsUnicode || ord < 0x100)
				str := SubStr(str, 1, j-1) . Chr(ord) . SubStr(str, j+6)
		}
		
		static ObjPush := Func(is_v2 ? "ObjPush" : "ObjInsert")
		%ObjPush%(strings, str)
	}

	key := "", is_key := false
	stack := [ tree := [] ]
	is_arr := { (tree): 1 }
	next := q . "{[01234567890-tfn"
	pos := 0
	while ( (ch := SubStr(src, ++pos, 1)) != "" )
	{
		if InStr(" `t`n`r", ch)
			continue
		if !InStr(next, ch)
			throw Exception("Unexpected char.", -1, ch)

		is_array := is_arr[obj := stack[1]]

		if i := InStr("{[", ch)
		{
			val := (proto := args[i]) ? new proto : {}
			is_array? %ObjPush%(obj, val) : obj[key] := val
			
			static ObjInsertAt := Func(is_v2 ? "ObjInsertAt" : "ObjInsert")
			%ObjInsertAt%(stack, 1, val)
			
			is_arr[val] := !(is_key := ch == "{")
			next := q . (is_key ? "}" : "{[]0123456789-tfn")
		}

		else if InStr("}]", ch)
		{
			static ObjRemoveAt := Func(is_v2 ? "ObjRemoveAt" : "ObjRemove")
			%ObjRemoveAt%(stack, 1)
			
			next := is_arr[stack[1]] ? "]," : "},"
		}

		else if InStr(",:", ch)
		{
			if (obj == tree)
				throw Exception("Unexpected char -> there is no container object.", -1, ch)
			
			is_key := (!is_array && ch == ",")
			next := q . "{[0123456789-tfn"
		}

		else
		{
			if (ch == q) ; string
			{
				val := %ObjRemoveAt%(strings, 1)
				if is_key
				{
					key := val, next := ":"
					continue
				}
			}

			else ; number, true|false|null
			{
				val := SubStr(src, pos, (SubStr(src, pos) ~= "[\]\},\s]|$")-1)
				pos += StrLen(val)-1
				if InStr("tfn", ch) ; case-insensitive to avoid casting it to 'else if'
				{
					static t := "true", f := "false", n := "null", null := ""
					if !(val == %ch%) ; case-sensitive comparison
						throw Exception(Format("Expected '{}' instead of '{}'.", %ch%, val), -1)
					val := %val%
				}
				else if (Abs(val) == "")
					throw Exception("Invalid number.", -1, val)
				val := val + 0 ; val += 0 on v1.1+ converts "" to 0
			}
			
			is_array? %ObjPush%(obj, val) : obj[key] := val
			next := is_array ? "]," : "},"
		}
	}

	return tree[1]
}

Jxon_Dump(obj, indent:="", lvl:=1)
{
	static q := Chr(34)

	if IsObject(obj)
	{
		if (ObjGetCapacity(obj) == "")
			throw Exception("Object type not supported.", -1, Format("<Object at 0x{:p}>", &obj))

		is_array := 0
		for k in obj
			is_array := k == A_Index
		until !is_array

		static integer := "integer"
		if indent is %integer%
		{
			if (indent < 0)
				throw Exception("Indent parameter must be a postive integer.", -1, indent)
			spaces := indent, indent := ""
			Loop % spaces
				indent .= " "
		}
		indt := ""
		Loop, % indent ? lvl : 0
			indt .= indent

		lvl += 1, out := "" ; Make #Warn happy
		for k, v in obj
		{
			if IsObject(k) || (k == "")
				throw Exception("Invalid JSON key", -1)
			
			if !is_array
				out .= ( ObjGetCapacity([k], 1) ? Jxon_Dump(k) : q . k . q ) ;// key
				    .  ( indent ? ": " : ":" ) ; token + padding
			out .= Jxon_Dump(v, indent, lvl) ; value
			    .  ( indent ? ",`n" . indt : "," ) ; token + indent
		}

		if (out != "")
		{
			out := Trim(out, ",`n" . indent)
			if (indent != "")
				out := "`n" . indt . out . "`n" . SubStr(indt, StrLen(indent)+1)
		}
		
		return is_array ? "[" . out . "]" : "{" . out . "}"
	}

	; Number
	else if (ObjGetCapacity([obj], 1) == "")
		return obj

	; String (null -> not supported by AHK)
	if (obj != "")
	{
		static Replace := Func(A_AhkVersion<"2" ? "RegExReplace" : "StrReplace")
		static bash := A_AhkVersion<"2" ? "\\" : "\"
		  obj := %Replace%(obj,  bash,    "\\")
		, obj := %Replace%(obj,   "/",    "\/")
		, obj := %Replace%(obj,     q, "\" . q)
		, obj := %Replace%(obj,  "`b",    "\b")
		, obj := %Replace%(obj,  "`f",    "\f")
		, obj := %Replace%(obj,  "`n",    "\n")
		, obj := %Replace%(obj,  "`r",    "\r")
		, obj := %Replace%(obj,  "`t",    "\t")

		static Ord := Func(A_AhkVersion<"2" ? "Asc" : "Ord")
		while RegExMatch(obj, "[^\x20-\x7e]", m)
			obj := %Replace%(obj, ch := IsObject(m) ? m[0] : m, Format("\u{:04X}", %Ord%(ch)))
	}
	
	return q . obj . q
}

Jxon_Read(src, prototype*)
{
	if f := FileOpen(src, "r", "UTF-8")
	{
		jstr := f.Read(), f.Close()
		return Jxon_Load(jstr, prototype*)
	}
}

Jxon_Write(obj, dest, indent:="")
{
	if f := FileOpen(dest, "w", "UTF-8")
	{
		bytes := f.Write(Jxon_Dump(obj, indent)), f.Close()
		return bytes
	}
}