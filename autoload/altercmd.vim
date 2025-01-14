" altercmd - Alter built-in Ex commands by your own ones
" Version: 0.0.0
" Copyright (C) 2009 kana <http://whileimautomaton.net/>
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
" Interface  "{{{1
function! altercmd#load()  "{{{2
  runtime! plugin/altercmd.vim
endfunction




function! altercmd#define(...)  "{{{2
  if a:0 == 2
    " For :AlterCommand family
    let [args, modes] = a:000
    try
      let [options, lhs_list, alternate_name] = s:parse_args(args)
    catch /^parse error$/
      call s:echomsg('WarningMsg', 'invalid argument')
      return
    endtry
  elseif a:0 >= 4
    " For altercmd#define() (function version).
    let [opt_chars, lhs, alternate_name, modes] = a:000
    let options = s:convert_options(opt_chars)
    let lhs_list = s:generate_lhs_list(lhs)
  else
    call s:echomsg('WarningMsg', 'invalid argument')
    return
  endif

  call s:do_define(options, lhs_list, alternate_name, modes)
endfunction

function! s:do_define(options, lhs_list, alternate_name, modes) "{{{2
  let options = a:options
  let lhs_list = a:lhs_list
  let alternate_name = a:alternate_name
  let modes = a:modes

  if get(options, 'cmdwin', 0)
    let opt = deepcopy(options, 1)
    let m = modes
    let t = get(opt, 'cmdtype', ':')

    " Avoid infinite recursion.
    silent! unlet opt.cmdwin
    silent! unlet opt.cmdtype
    " Cmdwin mappings should be buffer-local.
    let opt.buffer = 1
    " Cmdwin mappings should work only in insert-mode.
    let m = 'i'

    execute
    \ 'autocmd altercmd CmdwinEnter'
    \ t
    \ 'call'
    \ 's:do_define('
    \   string(opt) ','
    \   string(lhs_list) ','
    \   string(alternate_name) ','
    \   string(m) ','
    \ ')'

    return
  endif

  if get(options, 'expr', 0)
    let alternate_name = '<C-r>=' . alternate_name . '<CR>'
  endif

  " augroup altercmd-truncate_trailing_whitespace
  "   au CmdlineChanged : ++once call s:truncate_trailing_whitespace()
  " augroup END

  " TODO: Enable resonable expansion following `|`.
  " let pat_preceding = '\%(^\||\)\s*'
  let pat_preceding = '\%^\s*'

  let pat_mark = '''[a-zA-Z0-9<>\[\]<>''`"^.(){}]'
  let pat_match = '\([/?]\)[^\1]\{-}\%(\\\@<!\1\)\='
  let pat_previous = '\\[/?&]'
  let pat_address = '[.$]'
  \ . '\|\%([-+]\=[0-9]\+\)'
  \ . '\|\%(' . pat_mark     . '\)'
  \ . '\|\%(' . pat_match    . '\)'
  \ . '\|\%(' . pat_previous . '\)'
  let pat_address = '\%(' . pat_address . '\)'
  \ . '\s*\%([,;]\='
  \ . '\s*\%(' . pat_address .'\)\)\='
  let pat_range = '\%(\*\|%\)'
  \ . '\|\%(' . pat_address . '\)'
  " Truncate extra spaces for user to control format in ':AlterCommand'.
  let s:pat_range = '\s*\zs' . pat_range . '\ze\s*'

  for mode in split(modes, '\zs')
    for lhs in lhs_list
      if mode ==# 'c'
        if get(options, 'range', 0)
          let pat = pat_preceding . '\%(' . s:pat_range . '\)\=\s*' . lhs . '\s*$'
          let cond = 'getcmdtype() == ":"'
          \ . ' && getcmdline()[: getcmdpos() - 1] =~# ' . string(pat)
          let alternate_name = '<C-\>e<SID>expand_with_range('
          \ . string(alternate_name) . ')<CR>'
        else
          let pat = '^\s*' . lhs . '\s*$'
          let cond = 'getcmdtype() == ":" && getcmdline() =~# ' . string(pat)
        endif
      else
        let cond = '(getline(".") ==# ' . string(lhs) . ')'
      endif
      execute
      \ mode . 'noreabbrev <expr>' . (get(options, 'buffer', 0) ? '<buffer>' : '')
      \ lhs
      \ substitute(cond, '|', '<bar>', 'g')
      \ '?' substitute(string(alternate_name), '|', '<bar>', 'g')
      \ ':' string(lhs)
    endfor
  endfor
endfunction




function! s:echomsg(hi, msg) "{{{2
  execute 'echohl' a:hi
  echomsg a:msg
  echohl None
endfunction




function! s:skip_white(q_args) "{{{2
  return substitute(a:q_args, '^\s*', '', '')
endfunction

function! s:parse_one_arg_from_q_args(q_args) "{{{2
  let arg = s:skip_white(a:q_args)
  let head = matchstr(arg, '^.\{-}[^\\]\ze\([ \t]\|$\)')
  let rest = strpart(arg, strlen(head))
  return [head, rest]
endfunction

function! s:parse_options(args) "{{{2
  let args = a:args
  let opt = {}

  while args != ''
    let o = matchstr(args, '^<[^<>]\+>')
    if o == ''
      break
    endif
    let args = strpart(args, strlen(o))

    if o ==? '<expr>'
      let opt.expr = 1
    endif

    if o ==? '<buffer>'
      let opt.buffer = 1
    endif

    if o ==? '<range>'
      let opt.range = 1
    endif

    " <cmdwin>   : normal Ex command
    " <cmdwin:*> * all command line window
    " <cmdwin::> : normal Ex command
    " <cmdwin:d> > debug mode command |debug-mode|
    " <cmdwin:/> / forward search string
    " <cmdwin:?> ? backward search string
    " <cmdwin:=> = expression for "= |expr-register|
    " <cmdwin:@> @ string for |input()|
    " <cmdwin:-> - text for |:insert| or |:append|
    if o ==? '<cmdwin>'
      let opt.cmdwin = 1
    endif
    let m = matchlist(o, '^<cmdwin:\([*:d/?=@-]\)>$')
    if !empty(m)
      let opt.cmdwin = 1
      let opt.cmdtype = m[1] == 'd' ? '>' : m[1]
    endif

    let m = matchlist(o, '^<mode:\([nvoiclxs]\+\)>$')
    if !empty(m)
      let opt.modes = m[1]
    endif
  endwhile

  return [opt, args]
endfunction

function! s:parse_args(args)  "{{{2
  let parse_error = 'parse error'
  let args = a:args

  let [options, args] = s:parse_options(args)
  let [original_name, args] = s:parse_one_arg_from_q_args(args)
  let alternate_name = s:skip_white(args)

  return [options, s:generate_lhs_list(original_name), alternate_name]
endfunction




function! s:generate_lhs_list(lhs) "{{{2
  if a:lhs =~ '\['
    let [original_name_head, original_name_tail] = split(a:lhs, '[')
    let original_name_tail = substitute(original_name_tail, '\]', '', '')
  else
    let original_name_head = a:lhs
    let original_name_tail = ''
  endif

  let lhs_list = []
  let original_name_tail = ' ' . original_name_tail
  for i in range(len(original_name_tail))
    let lhs = original_name_head . original_name_tail[1:i]
    call add(lhs_list, lhs)
  endfor

  return lhs_list
endfunction

function! s:convert_options(opt_chars) "{{{2
  let table = {'b': 'buffer', 'C': 'cmdwin'}
  let options = {}
  for c in split(a:opt_chars, '\zs')
    if has_key(table, c)
      let options[table[c]] = 1
    endif
  endfor
  return options
endfunction




function! s:expand_with_range(alternate) abort
  let cmdline = getcmdline()
  let cmdpos = getcmdpos()
  let preceding = cmdline[: cmdpos - 1]
  let [range, start, end] = matchstrpos(preceding, s:pat_range)
  let new_alternate = substitute(a:alternate, '<range>', range, 'g')
  if range ==# ''
    let following = cmdline[cmdpos :]
  else
    let preceding = start == 0 ? '' : cmdline[: start - 1]
    let following = cmdline[end + 1 :]
  endif
  let new_cmdline = preceding . new_alternate . following
  return new_cmdline
endfunction




function! s:truncate_trailing_whitespace() abort

endfunction

" __END__  "{{{1
" vim: foldmethod=marker
