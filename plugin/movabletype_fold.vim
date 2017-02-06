
if exists('loaded_movabletype_fold') || &cp
    finish
endif
let loaded_movabletype_fold = 1

command! -bar MovableTypeFoldToggle call movabletype_fold#toggle()
