#include "<df>/const.h"

extern Putc
extern Malloc

(* any new procedures or changes to structs should be updated in <df>/rt.h *)

procedure CR (* -- *)
	'\n' Putc
end

procedure Call (* ... ptr -- ... *)
	asm "

	popv r5, r0
	br r0

	"
end

procedure abs (* v -- absv *)
	auto v
	v!

	if (v@ 0 s<)
		0 v@ - return
	end

	v@
end

procedure max (* n1 n2 -- max *)
	auto n2
	n2!

	auto n1
	n1!

	if (n2@ n1@ >) n2@ end else n1@ end
end

procedure min (* n1 n2 -- min *)
	auto n2
	n2!

	auto n1
	n1!

	if (n2@ n1@ <) n2@ end else n1@ end
end

procedure itoa (* n buf -- *)
	auto str
	str!

	auto n
	n!

	auto i
	0 i!

	while (1)
		n@ 10 % '0' + str@ i@ + sb
		i@ 1 + i!
		n@ 10 / n!
		if (n@ 0 ==)
			break
		end
	end

	0 str@ i@ + sb
	str@ reverse
end

procedure strdup (* str -- allocstr *)
	auto str
	str!

	auto astr
	str@ strlen 1 + Malloc astr!

	astr@ str@ strcpy

	astr@
end

procedure reverse (* str -- *)
	auto str
	str!

	auto i
	auto j
	auto c

	0 i!
	str@ strlen 1 - j!

	while (i@ j@ <)
		str@ i@ + gb c!

		str@ j@ + gb str@ i@ + sb
		c@ str@ j@ + sb

		i@ 1 + i!
		j@ 1 - j!
	end
end

procedure memcpy (* dest src size -- *)
	auto sz
	sz!

	auto src
	src!

	auto dest
	dest!

	auto i
	0 i!

	auto iol
	sz@ 4 / iol!

	auto rm
	sz@ 4 % rm!

	while (i@ iol@ <)
		src@ @ dest@ !

		src@ 4 + src!
		dest@ 4 + dest!
		i@ 1 + i!
	end

	0 i!

	while (i@ rm@ <)
		src@ gb dest@ sb

		src@ 1 + src!
		dest@ 1 + dest!
		i@ 1 + i!
	end
end

procedure memset (* ptr size wot -- *)
	auto wot
	wot!

	auto size
	size!

	auto ptr
	ptr!

	auto iol
	size@ 4 / iol!

	auto rm
	size@ 4 % rm!

	auto i
	0 i!

	while (i@ iol@ <)
		wot@ ptr@ !
		ptr@ 4 + ptr!
		i@ 1 + i!
	end

	0 i!

	while (i@ rm@ <)
		wot@ ptr@ sb

		ptr@ 1 + ptr!
		i@ 1 + i!
	end
end

procedure strcmp (* str1 str2 -- equal? *)
	auto str1
	str1!

	auto str2
	str2!

	auto i
	0 i!

	while (str1@ i@ + gb str2@ i@ + gb ==)
		if (str1@ i@ + gb 0 ==)
			1 return
		end

		i@ 1 + i!
	end

	0 return
end

procedure strlen (* str -- size *)
	auto str
	str!

	auto size
	0 size!

	while (str@ gb 0 ~=)
		size@ 1 + size!
		str@ 1 + str!
	end

	size@ return
end

procedure strtok (* str buf del -- next *)
	auto del
	del!

	auto buf
	buf!

	auto str
	str!

	auto i
	0 i!

	if (str@ gb 0 ==)
		0 buf@ sb
		0 return
	end

	while (str@ gb del@ ==)
		str@ 1 + str!
	end

	while (str@ i@ + gb del@ ~=)
		auto char
		str@ i@ + gb char!

		char@ buf@ i@ + sb

		if (char@ 0 ==)
			0 return
		end

		i@ 1 + i!
	end

	0 buf@ i@ + sb

	str@ i@ +
end

procedure strzero (* str -- *)
	auto str
	str!

	auto i
	0 i!
	while (str@ i@ + gb 0 ~=)
		0 str@ i@ + sb
		i@ 1 + i!
	end
end

procedure strntok (* str buf del n -- next *)
	auto n
	n!

	auto del
	del!

	auto buf
	buf!

	auto str
	str!

	auto i
	0 i!

	if (str@ gb 0 ==)
		0 buf@ sb
		0 return
	end

	while (str@ gb del@ ==)
		str@ 1 + str!
	end

	while (str@ i@ + gb del@ ~=)
		if (i@ n@ >)
			break
		end

		auto char
		str@ i@ + gb char!

		char@ buf@ i@ + sb

		if (char@ 0 ==)
			0 return
		end

		i@ 1 + i!
	end

	0 buf@ i@ + sb

	str@ i@ +
end

procedure strcpy (* dest src -- *)
	auto src
	src!
	auto dest
	dest!

	while (src@ gb 0 ~=)
		src@ gb dest@ sb

		dest@ 1 + dest!
		src@ 1 + src!
	end

	0 dest@ sb
end

procedure strncpy (* dest src max -- *)
	auto max
	max!

	auto src
	src!

	auto dest
	dest!

	dest@ max@ + max!

	while (src@ gb 0 ~= dest@ max@ < &&)
		src@ gb dest@ sb

		dest@ 1 + dest!
		src@ 1 + src!
	end

	0 dest@ sb
end

procedure strcat (* dest src -- *)
	auto src
	src!

	auto dest
	dest!

	dest@ strlen 1 + dest@ + src@ strcpy
end

procedure strncat (* dest src max -- *)
	auto max
	max!

	auto src
	src!

	auto dest
	dest!

	auto ds
	dest@ strlen 1 + ds!

	auto md
	max@ ds@ - md!

	ds@ dest@ + src@ md@ strncpy
end

procedure atoi (* str -- n *)
	auto str
	str!

	auto i
	auto res
	0 i!
	0 res!
	while (str@ i@ + gb 0 ~=)
		res@ 10 *
		str@ i@ + gb '0' -
		+
		res!

		i@ 1 + i!
	end
	res@ return
end

table KConsoleDigits
	'0' '1' '2' '3' '4' '5' '6' '7' '8' '9' 'a' 'b' 'c' 'd' 'e' 'f'
endtable

procedure Puts (* s -- *)
	auto s
	s!

	while (s@ gb 0 ~=)
		s@ gb Putc
		s@ 1 + s!
	end
end

procedure Putx (* nx -- *)
	auto nx
	nx!

	if (nx@ 15 >)
		auto a
		nx@ 16 / a!

		nx@ 16 a@ * - nx!
		a@ Putx
	end

	[nx@]KConsoleDigits@ Putc
end

procedure Putn (* n -- *)
	auto n
	n!

	if (n@ 9 >)
		auto a
		n@ 10 / a!

		n@ 10 a@ * - n!
		a@ Putn
	end

	[n@]KConsoleDigits@ Putc
end

procedure Printf (* ... fmt -- *)
	auto f
	f!
	auto i
	0 i!
	auto sl
	f@ strlen sl!
	while (i@ sl@ <)
		auto char
		f@ i@ + gb char!
		if (char@ '%' ~=)
			char@ Putc
		end else
			i@ 1 + i!
			if (i@ sl@ >=)
				return
			end

			f@ i@ + gb char!

			if (char@ 'd' ==)
				Putn
			end else

			if (char@ 'x' ==)
				Putx
			end else

			if (char@ 's' ==)
				Puts
			end else

			if (char@ '%' ==)
				'%' Putc
			end else

			if (char@ 'l' ==)
				Putc
			end

			end

			end

			end

			end
		end

		i@ 1 + i!
	end
end