install:
	install -m 0555 wunderlist-backup.rb $(DESTDIR)/usr/bin/wunderlist-backup

uninstall:
	rm -f $(DESTDIR)/usr/bin/wunderlist-backup
