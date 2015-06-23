
checkCalendar: checkCalendar.hs
	ghc -O3 -Wall $<

clean: checkCalendar
	rm $<

install: checkCalendar
	install $< $(HOME)/bin/

uninstall:
	rm $(HOME)/bin/checkCalendar
