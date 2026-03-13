on adding folder items to thisFolder after receiving addedItems
	repeat with anItem in addedItems
		set filePath to POSIX path of anItem
		do shell script quoted form of (POSIX path of (path to home folder) & "dotfiles/bin/watch-downloads-copy") & " " & quoted form of filePath
	end repeat
end adding folder items to
