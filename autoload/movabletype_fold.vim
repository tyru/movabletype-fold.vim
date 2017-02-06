
let s:ENTRY_DELIM = '--------'
let s:SECTION_DELIM = '-----'

" Parse the containing section
" if the result of current version & lnum was not cached
function! movabletype_fold#foldexpr(lnum) abort
  if a:lnum ==# len(s:get_content())
    return 0
  endif
  let entry = s:get_entry_by_lnum(a:lnum)
  return s:get_foldlevel(a:lnum, entry)
endfunction

function! movabletype_fold#foldtext(lnum) abort
  let entry = s:get_entry_by_lnum(a:lnum)
  let metadata = s:parse_metadata(entry)
  " 'MM/DD/YYYY hh:mm:ss AM|PM' -> 'YYYY/MM/DD hh:mm'
  if has_key(metadata, 'DATE')
    let m = matchlist(metadata['DATE'][0], '\(\d\{2}\)/\(\d\{2}\)/\(\d\{4}\) \(\d\{2}\):\(\d\{2}\):\(\d\{2}\)\( AM\| PM\)\?')
    if !empty(m)
      let [MM, DD, YYYY, hh, mm, ss, ampm; _] = m[1:]
      if ampm ==# ' PM'
        let hh += 12
      endif
      let metadata['DATE'][0] = printf('%s/%s/%s %s:%s', YYYY, +MM, +DD, +hh, +mm)
    endif
  endif
  let header = repeat('#', foldlevel(a:lnum))
  let categories = !has_key(metadata, 'CATEGORY') ? '' : '[' . join(metadata['CATEGORY'], '][') . '] '
  let title = s:get_nest(metadata, ['TITLE', 0], '(null)')
  let date = s:get_nest(metadata, ['DATE', 0], '0000/00/00 00:00')
  return printf('%s %s%s (%s)', header, categories, title, date)
endfunction

function! s:get_nest(obj, keys, default) abort
  return len(a:keys) == 0 ? a:default :
  \      len(a:keys) == 1 ? get(a:obj, a:keys[0], a:default) :
  \      s:get_nest(get(a:obj, a:keys[0], a:default), a:keys[1:], a:default)
endfunction

function! movabletype_fold#toggle() abort
  if !exists('b:movable_type_fold')
    echo 'Caching...'
    let b:movable_type_fold = {
    \ 'foldmethod': &foldmethod,
    \ 'foldexpr': &foldexpr,
    \ 'foldtext': &foldtext,
    \ 'version': ''
    \}
    setlocal foldmethod=expr
    setlocal foldexpr=movabletype_fold#foldexpr(v:lnum)
    setlocal foldtext=movabletype_fold#foldtext(v:foldstart)
    foldclose!
    echon "\rCaching... done."
  else
    let &l:foldmethod = b:movable_type_fold.foldmethod
    let &l:foldexpr = b:movable_type_fold.foldexpr
    let &l:foldtext = b:movable_type_fold.foldtext
    unlet b:movable_type_fold
    normal! zE
  endif
endfunction

" b:movable_type_fold = {
"   ...,
"   cache_lnum: [
"     { from: <from>, to: <to>, foldlevel: <foldlevel(integer)> }
"   ],
"   cache_content: [ <lines of current version of buffer> ]
" }
" NOTE: This affects `b:movable_type_fold.cache_*` variables.
function! s:init_movable_type_fold(ver) abort
  let b:movable_type_fold.cache_content = getline(1, '$')
  let b:movable_type_fold.cache_lnum = []
  let b:movable_type_fold.version = a:ver
endfunction

" Get current version of entry.
" NOTE: This affects `b:movable_type_fold.cache_*` variables.
function! s:get_entry_by_lnum(lnum) abort
  let ver = s:get_file_version()
  if b:movable_type_fold.version !=# ver
    call s:init_movable_type_fold(ver)
    let entry = s:parse_section(s:get_content(), a:lnum)
    let b:movable_type_fold.cache_lnum += [entry]
    return entry
  endif
  let entries = b:movable_type_fold.cache_lnum
  let res = s:bsearch_index(entries, a:lnum)
  if res.found
    return entries[res.index]
  else
    let entry = s:parse_section(s:get_content(), a:lnum)
    call s:add_entry(entries, entry)
    return entry
  endif
endfunction

" NOTE: This affects `b:movable_type_fold.cache_*` variables.
function! s:get_content() abort
  let ver = s:get_file_version()
  if b:movable_type_fold.version !=# ver
    call s:init_movable_type_fold(ver)
  endif
  return b:movable_type_fold.cache_content
endfunction

function! s:add_entry(entries, entry) abort
  let res = s:bsearch_index(a:entries, a:entry.from)
  if !res.found
    call insert(a:entries, a:entry, res.index)
  endif
endfunction

" @return {Dictionary} { found: <Boolean>, index: <Integer> }
function! s:bsearch_index(entries, lnum) abort
  if empty(a:entries)
    return {'found': 0, 'index': 0}
  endif
  let min = 0
  let max = len(a:entries) - 1
  while max - min > 10
    let mid = (min + max) / 2
    if a:entries[mid].from > a:lnum
      let max = mid
    else
      let min = mid
    endif
  endwhile
  " Fallback to linear search
  for i in range(min, max)
    if a:entries[i].from <= a:lnum && a:lnum <= a:entries[i].to
      return {'found': 1, 'index': i}
    elseif a:entries[i].from > a:lnum
      return {'found': 0, 'index': i}
    endif
  endfor
  return {'found': 0, 'index': max + 1}
endfunction

" Parse the section containing lnum
" @return {Dictionary} { from: <from>, to: <to>, foldlevel: <foldlevel> }
function! s:parse_section(lines, lnum) abort
  let from = s:find_section_delim_lnum_from(a:lines, a:lnum, -1)
  if from ==# 0
    let from = 1
  endif
  let to = s:find_section_delim_lnum_from(a:lines, a:lnum + 1, +1)
  if to ==# 0
    let to = len(a:lines)
  endif
  return {
  \ 'from': from,
  \ 'to': to - 1,
  \ 'foldlevel': 1
  \}
endfunction

function! s:get_foldlevel(lnum, entry) abort
  return a:lnum == a:entry.from ? a:entry.foldlevel :
  \      a:lnum == a:entry.to ? '<' . a:entry.foldlevel :
  \      '='
endfunction

" @return {Integer} lnum of delimiter. 0 when failed to look up
function! s:find_section_delim_lnum_from(lines, lnum, step) abort
  let lnum = a:lnum
  let max = len(a:lines) - 1
  while 1 <= lnum && lnum <= max
    if a:lines[lnum - 1] ==# s:ENTRY_DELIM
      return lnum
    endif
    let lnum += a:step
  endwhile
  return 0
endfunction

if has('*undotree')
    function! s:get_file_version() abort
        return undotree().seq_cur
    endfunction
else
    function! s:get_file_version() abort
        return b:changedtick
    endfunction
endif

function! s:parse_metadata(entry) abort
  let lines = getline(a:entry.from, a:entry.to)
  let end = index(lines, s:SECTION_DELIM)
  if end ==# -1
    return {}
  endif
  let metadata = {}
  for line in lines[: end - 1]
    let m = matchlist(line, '\([^:]\+\): \(.*\)')
    if !empty(m)
      let metadata[m[1]] = get(metadata, m[1], []) + [m[2]]
    endif
  endfor
  return metadata
endfunction
