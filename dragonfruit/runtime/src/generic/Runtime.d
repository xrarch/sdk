#include "<df>/const.h"

extern Putc
extern Malloc
extern Getc

(* any new procedures should be updated in <df>/rt.h *)

procedure CR (* -- *)
	'\n' Putc
end

procedure abs { v -- absv }
	v@ absv!

	if (v@ 0 s<)
		0 v@ - absv!
	end
end

procedure max { n1 n2 } (* -- max *)
	if (n2@ n1@ >) n2@ end else n1@ end
end

procedure min { n1 n2 } (* -- min *)
	if (n2@ n1@ <) n2@ end else n1@ end
end

procedure itoa { n str -- }
	auto i
	0 i!

	while (1)
		n@ 10 % '0' + str@ i@ + sb
		1 i +=
		10 n /=
		if (n@ 0 ==)
			break
		end
	end

	0 str@ i@ + sb
	str@ reverse
end

procedure strdup { str -- astr }
	str@ strlen 1 + Malloc astr!

	astr@ str@ strcpy
end

procedure reverse { str -- }
	auto i
	auto j
	auto c

	0 i!
	str@ strlen 1 - j!

	while (i@ j@ <)
		str@ i@ + gb c!

		str@ j@ + gb str@ i@ + sb
		c@ str@ j@ + sb

		1 i +=
		1 j -=
	end
end

procedure memcpy { dest src sz -- }
	auto i
	0 i!

	auto iol
	sz@ 4 / iol!

	auto rm
	sz@ 4 % rm!

	while (i@ iol@ <)
		src@ @ dest@ !

		4 src +=
		4 dest +=
		1 i +=
	end

	0 i!

	while (i@ rm@ <)
		src@ gb dest@ sb

		1 src +=
		1 dest +=
		1 i +=
	end
end

procedure memset { ptr size wot -- }
	auto iol
	size@ 4 / iol!

	auto rm
	size@ 4 % rm!

	auto i
	0 i!

	while (i@ iol@ <)
		wot@ ptr@ !

		4 ptr +=
		1 i +=
	end

	0 i!

	while (i@ rm@ <)
		wot@ ptr@ sb

		1 ptr +=
		1 i +=
	end
end

procedure strcmp { str1 str2 } (* -- equal? *)
	auto i
	0 i!

	while (str1@ i@ + gb str2@ i@ + gb ==)
		if (str1@ i@ + gb 0 ==)
			1 return
		end

		1 i +=
	end

	0 return
end

procedure strlen { str -- size }
	0 size!

	while (str@ gb 0 ~=)
		1 size +=
		1 str +=
	end
end

procedure strtok { str buf del -- next }
	auto i
	0 i!

	if (str@ gb 0 ==)
		0 buf@ sb
		0 next!
		return
	end

	while (str@ gb del@ ==)
		1 str +=
	end

	while (str@ i@ + gb del@ ~=)
		auto char
		str@ i@ + gb char!

		char@ buf@ i@ + sb

		if (char@ 0 ==)
			0 next!
			return
		end

		1 i +=
	end

	0 buf@ i@ + sb

	str@ i@ + next!
end

procedure strzero { str -- }
	auto i
	0 i!
	while (str@ i@ + gb 0 ~=)
		0 str@ i@ + sb
		
		1 i +=
	end
end

procedure strntok { str buf del n -- next }
	auto i
	0 i!

	if (str@ gb 0 ==)
		0 buf@ sb
		0 next!
		return
	end

	while (str@ gb del@ ==)
		1 str +=
	end

	while (str@ i@ + gb del@ ~=)
		if (i@ n@ >)
			break
		end

		auto char
		str@ i@ + gb char!

		char@ buf@ i@ + sb

		if (char@ 0 ==)
			0 next!
			return
		end

		1 i +=
	end

	0 buf@ i@ + sb

	str@ i@ + next!
end

procedure strcpy { dest src -- }
	while (src@ gb 0 ~=)
		src@ gb dest@ sb

		1 dest +=
		1 src +=
	end

	0 dest@ sb
end

procedure strncpy { dest src max -- }
	dest@ max@ + max!

	while (src@ gb 0 ~= dest@ max@ < &&)
		src@ gb dest@ sb

		1 dest +=
		1 src +=
	end

	0 dest@ sb
end

procedure strcat { dest src -- }
	dest@ strlen 1 + dest@ + src@ strcpy
end

procedure strncat { dest src max -- }
	auto ds
	dest@ strlen 1 + ds!

	auto md
	max@ ds@ - md!

	ds@ dest@ + src@ md@ strncpy
end

procedure atoi { str -- res }
	auto i
	0 i!
	0 res!
	while (str@ i@ + gb 0 ~=)
		res@ 10 *
		str@ i@ + gb '0' -
		+
		res!

		1 i +=
	end
end

table KConsoleDigits
	'0' '1' '2' '3' '4' '5' '6' '7' '8' '9' 'a' 'b' 'c' 'd' 'e' 'f'
endtable

procedure Puts { s -- }
	while (s@ gb 0 ~=)
		s@ gb Putc
		1 s +=
	end
end

procedure Putx { nx -- }
	if (nx@ 15 >)
		auto a
		nx@ 16 / a!

		nx@ 16 a@ * - nx!
		a@ Putx
	end

	[nx@]KConsoleDigits@ Putc
end

procedure Putn { n -- }
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
			1 i +=
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

		1 i +=
	end
end

procedure Gets { s max -- }
	auto len
	0 len!

	while (1)
		auto c
		ERR c!
		while (c@ ERR ==)
			Getc c!
		end

		if (c@ '\n' ==)
			'\n' Putc
			break
		end

		if (c@ '\b' ==)
			if (len@ 0 >)
				1 len -=
				0 s@ len@ + sb
				'\b' Putc
				' ' Putc
				'\b' Putc
			end
		end else if (len@ max@ <)
			c@ s@ len@ + sb

			1 len +=
			c@ Putc
		end end
	end

	0 s@ len@ + sb
end