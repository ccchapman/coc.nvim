let s:is_vim = !has('nvim')
let s:prefix = '[List Preview]'
" filetype detect could be slow.
let s:filetype_map = {
  \ 'vim': 'vim',
  \ 'ts': 'typescript',
  \ 'js': 'javascript',
  \ 'html': 'html',
  \ 'css': 'css'
  \ }

function! coc#list#getchar() abort
  return coc#prompt#getchar()
endfunction

function! coc#list#setlines(lines, append)
  if a:append
    silent call append(line('$'), a:lines)
  else
    silent call append(0, a:lines)
    if exists('*deletebufline')
      call deletebufline('%', len(a:lines) + 1, '$')
    else
      let n = len(a:lines) + 1
      let saved_reg = @"
      silent execute n.',$d'
      let @" = saved_reg
    endif
  endif
endfunction

function! coc#list#options(...)
  let list = ['--top', '--tab', '--normal', '--no-sort', '--input', '--strict',
        \ '--regex', '--interactive', '--number-select', '--auto-preview',
        \ '--ignore-case', '--no-quit', '--first']
  if get(g:, 'coc_enabled', 0)
    let names = coc#rpc#request('listNames', [])
    call extend(list, names)
  endif
  return join(list, "\n")
endfunction

function! coc#list#names(...) abort
  let names = coc#rpc#request('listNames', [])
  return join(names, "\n")
endfunction

function! coc#list#status(name)
  if !exists('b:list_status') | return '' | endif
  return get(b:list_status, a:name, '')
endfunction

function! coc#list#create(position, height, name, numberSelect)
  if a:position ==# 'tab'
    execute 'silent tabe list:///'.a:name
  else
    execute 'silent keepalt '.(a:position ==# 'top' ? '' : 'botright').a:height.'sp list:///'.a:name
    execute 'resize '.a:height
  endif
  if a:numberSelect
    setl norelativenumber
    setl number
  else
    setl nonumber
    setl norelativenumber
    setl signcolumn=yes
  endif
  return [bufnr('%'), win_getid()]
endfunction

" close list windows
function! coc#list#clean_up() abort
  for i in range(1, winnr('$'))
    let bufname = bufname(winbufnr(i))
    if bufname =~# 'list://'
      execute i.'close!'
    endif
  endfor
endfunction

function! coc#list#setup(source)
  let b:list_status = {}
  setl buftype=nofile nobuflisted nofen nowrap
  setl norelativenumber bufhidden=wipe cursorline winfixheight
  setl tabstop=1 nolist nocursorcolumn undolevels=-1
  setl signcolumn=auto
  if has('nvim-0.5.0') || has('patch-8.1.0864')
    setl scrolloff=0
  endif
  if exists('&cursorlineopt')
    setl cursorlineopt=both
  endif
  setl filetype=list
  syntax case ignore
  let source = a:source[8:]
  let name = toupper(source[0]).source[1:]
  execute 'syntax match Coc'.name.'Line /\v^.*$/'
  nnoremap <silent><nowait><buffer> <esc> <C-w>c
endfunction

" Check if previewwindow exists on current tab.
function! coc#list#has_preview()
  for i in range(1, winnr('$'))
    let preview = getwinvar(i, 'previewwindow', getwinvar(i, '&previewwindow', 0))
    if preview
      return i
    endif
  endfor
  return 0
endfunction

" Get previewwindow from tabnr, use 0 for current tab
function! coc#list#get_preview(...) abort
  let tabnr = get(a:, 1, 0) == 0 ? tabpagenr() : a:1
  let info = gettabinfo(tabnr)
  if !empty(info)
    for win in info[0]['windows']
      if getwinvar(win, 'previewwindow', 0)
        return win
      endif
    endfor
  endif
  return -1
endfunction

function! coc#list#scroll_preview(dir) abort
  let winnr = coc#list#has_preview()
  if !winnr
    return
  endif
  let winid = win_getid(winnr)
  if exists('*win_execute')
    call win_execute(winid, "normal! ".(a:dir ==# 'up' ? "\<C-u>" : "\<C-d>"))
  else
    let id = win_getid()
    noa call win_gotoid(winid)
    execute "normal! ".(a:dir ==# 'up' ? "\<C-u>" : "\<C-d>")
    noa call win_gotoid(id)
  endif
endfunction

function! coc#list#restore(winid, height)
  let res = win_gotoid(a:winid)
  if res == 0 | return | endif
  if winnr('$') == 1
    return
  endif
  execute 'resize '.a:height
  if s:is_vim
    redraw
  endif
endfunction

function! coc#list#set_height(height) abort
  if winnr('$') == 1| return | endif
  execute 'resize '.a:height
endfunction

function! coc#list#hide(original, height, winid) abort
  let arr = win_id2tabwin(a:winid)
  " close preview window
  if !empty(arr) && arr[0] != 0
    silent! pclose!
    let previewwin = coc#list#get_preview(arr[0])
    call s:close_win(previewwin)
  endif
  if !empty(getwininfo(a:original))
    call win_gotoid(a:original)
  endif
  if a:winid
    call s:close_win(a:winid)
  endif
  if !empty(a:height) && win_getid() == a:original
    if exists('*nvim_win_set_height')
      call nvim_win_set_height(a:original, a:height)
    elseif win_getid() == a:original
      execute 'resize '.a:height
    endif
  endif
endfunction

function! s:close_win(winid) abort
  if empty(a:winid) || a:winid == -1 || empty(getwininfo(a:winid))
    return
  endif
  if s:is_vim
    if exists('*win_execute')
      noa call win_execute(a:winid, 'close!', 'silent!')
    else
      if win_getid() == a:winid
        noa silent! close!
      else
        let winid = win_getid()
        let res = win_gotoid(winid)
        if res
          noa silent! close!
          noa wincmd p
        endif
      endif
    endif
  else
    if nvim_win_is_valid(a:winid)
      silent! noa call nvim_win_close(a:winid, 1)
    endif
  endif
endfunction

" Improve preview performance by reused window & buffer.
" lines - list of lines
" config.position - could be 'below' 'top' 'tab'.
" config.name - (optional )name of preview buffer.
" config.splitRight - (optional) split to right when 1.
" config.lnum - (optional) current line number
" config.filetype - (optional) filetype of lines.
" config.hlGroup - (optional) highlight group.
" config.maxHeight - (optional) max height of window, valid for 'below' & 'top' position.
function! coc#list#preview(lines, config) abort
  if s:is_vim && !exists('*win_execute')
    echoerr 'win_execute function required for preview, please upgrade your vim.'
    return
  endif
  let winid = coc#list#get_preview(0)
  if empty(a:lines)
    call s:close_win(winid)
    return
  endif
  let bufnr = winid == -1 ? 0 : winbufnr(winid)
  " Try reuse buffer & window
  let bufnr = coc#float#create_buf(bufnr, a:lines)
  if bufnr == 0
    return
  endif
  call setbufvar(bufnr, '&synmaxcol', 500)
  let name = get(a:config, 'name', '')
  let filetype = get(a:config, 'filetype', '')
  let extname = matchstr(name, '\.\zs[^.]\+$')
  if empty(filetype) && !empty(extname)
    let filetype = get(s:filetype_map, extname, '')
  endif
  let range = get(a:config, 'range', v:null)
  let hlGroup = get(a:config, 'hlGroup', 'Search')
  let lnum = get(a:config, 'lnum', 1)
  let position = get(a:config, 'position', 'below')
  if winid == -1
    let change = position != 'tab' && get(a:config, 'splitRight', 0)
    let curr = win_getid()
    "noa above sb +5 52
    if change
      noa wincmd t
      execute 'noa belowright vnew +b\ '.bufnr
      let winid = win_getid()
    elseif position == 'tab' || get(a:config, 'splitRight', 0)
      execute 'noa belowright vnew +b\ '.bufnr
      let winid = win_getid()
    else
      let mod = position == 'top' ? 'below' : 'above'
      let height = s:get_height(a:lines, a:config)
      execute 'noa '.mod.' '.height.'new +b\ '.bufnr
      let winid = win_getid()
    endif
    execute 'noa exe '.lnum
    call setwinvar(winid, '&signcolumn', 'no')
    call setwinvar(winid, '&number', 1)
    call setwinvar(winid, '&cursorline', 0)
    call setwinvar(winid, '&relativenumber', 0)
    call setwinvar(winid, 'previewwindow', 1)
    noa call win_gotoid(curr)
  else
    let height = s:get_height(a:lines, a:config)
    if height > 0
      if s:is_vim
        let curr = win_getid()
        noa call win_gotoid(winid)
        execute 'silent! noa resize '.height
        noa call win_gotoid(curr)
      else
        call nvim_win_set_height(winid, height)
      endif
    endif
    call coc#float#execute(winid, ['syntax clear', 'noa call winrestview({"lnum":'.lnum.',"topline":'.max([1, lnum - 3]).'})'])
  endif
  if s:prefix.' '.name != bufname(bufnr)
    if s:is_vim
      call win_execute(winid, 'noa file '.fnameescape(s:prefix.' '.name), 'silent!')
    else
      silent! noa call nvim_buf_set_name(bufnr, s:prefix.' '.name)
    endif
  endif
  " highlights
  if !empty(filetype)
    let start = max([0, lnum - 300])
    let end = min([len(a:lines), lnum + 300])
    call coc#highlight#highlight_lines(winid, [{'filetype': filetype, 'startLine': start, 'endLine': end}])
    call coc#float#execute(winid, 'syn sync fromstart')
    "call coc#float#execute(winid, 'setfiletype '.filetype)
  else
    call coc#float#execute(winid, 'filetype detect')
    let ft = getbufvar(bufnr, '&filetype', '')
    if !empty(extname) && !empty(ft)
      let s:filetype_map[extname] = ft
    endif
  endif
  call sign_unplace('coc', {'buffer': bufnr})
  call coc#float#execute(winid, 'call clearmatches()')
  if !empty(range)
    call sign_place(1, 'coc', 'CocCurrentLine', bufnr, {'lnum': lnum})
    call coc#highlight#match_ranges(winid, bufnr, [range], hlGroup, 10)
  endif
  redraw
endfunction

function! s:get_height(lines, config) abort
  if get(a:config, 'splitRight', 0) || get(a:config, 'position', 'below') == 'tab'
    return 0
  endif
  let height = min([get(a:config, 'maxHeight', 10), len(a:lines), &lines - &cmdheight - 2])
  return height
endfunction
