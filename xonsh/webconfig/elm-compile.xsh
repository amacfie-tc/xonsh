#!/usr/bin/env xonsh
"""script for compiling elm source and dumping it to the js folder."""
import os
import io

from pygments.formatters.html import HtmlFormatter

from xonsh.tools import print_color, format_color
from xonsh.style_tools import partial_color_tokenize
from xonsh.color_tools import rgb_to_ints
from xonsh.pyghooks import XonshStyle, xonsh_style_proxy, XonshHtmlFormatter, Token
from xonsh.prompt.base import PromptFormatter


$RAISE_SUBPROC_ERROR = True
$XONSH_SHOW_TRACEBACK = False

#
# helper funcs
#

def escape(s):
    return s.replace("\n", "").replace('"', '\\"')


def invert_color(orig):
    r, g, b = rgb_to_ints(orig)
    inverted = [255 - r, 255 - g, 255 - b]
    new = [hex(n)[2:] for n in inverted]
    new = [n if len(n) == 2 else '0' + n for n in new]
    return ''.join(new)


def html_format(s, style="default"):
    buf = io.StringIO()
    proxy_style = xonsh_style_proxy(XonshStyle(style))
    # make sure we have a foreground color
    fgcolor = proxy_style._styles[Token.Text][0]
    if not fgcolor:
        fgcolor = invert_color(proxy_style.background_color[1:].strip('#'))
    # need to generate stream before creating formatter so that all tokens actually exist
    token_stream = partial_color_tokenize(s)
    formatter = XonshHtmlFormatter(
        wrapcode=True,
        noclasses=True,
        style=proxy_style,
        prestyles="margin: 0em; padding: 0.5em 0.1em; color: #" + fgcolor,
        cssstyles="border-style: solid; border-radius: 5px",
    )
    formatter.format(token_stream, buf)
    return buf.getvalue()


#
# first, write out elm-src/XonshData.elm
#
XONSH_DATA_HEADER = """-- A collection of xonsh values for the web-ui
-- This file has been auto-generated by elm-compile.xsh
module XonshData exposing (..)

import List
import String

"""

# render prompts
PROMPTS = [
    ("Default", '{env_name}{BOLD_GREEN}{user}@{hostname}{BOLD_BLUE} {cwd}'
                '{branch_color}{curr_branch: {}}{NO_COLOR} {BOLD_BLUE}'
                '{prompt_end}{NO_COLOR} '),
    ("Just a Dollar", "$ "),
]

prompt_header = """type alias PromptData =
    { name : String
    , value : String
    , display : String
    }

prompts : List PromptData
prompts ="""

def render_prompts(lines):
    prompt_format = PromptFormatter()
    fields = dict($PROMPT_FIELDS)
    fields.update(
        cwd="~/snail/stuff",
        user="lou",
        hostname="carcolh",
        env_name=fields['env_prefix'] + "env" + fields["env_postfix"],
        curr_branch="branch",
        branch_color="{BOLD_INTENSE_RED}",
    )
    lines.append(prompt_header)
    for i, (name, template) in enumerate(PROMPTS):
        display = html_format(prompt_format(template, fields=fields))
        #print(display)
        item = 'name = "' + name + '", '
        item += 'value = "' + escape(template) + '", '
        item += 'display = "' + escape(display) + '"'
        pre = "    [ " if i == 0 else "    , "
        lines.append(pre + "{ " + item + " }")
    lines.append("    ]")


def write_xonsh_data():
    # write XonshData.elm
    lines = [XONSH_DATA_HEADER]
    render_prompts(lines)
    src = "\n".join(lines) + "\n"
    xdelm = os.path.join('elm-src', 'XonshData.elm')
    with open(xdelm, 'w') as f:
        f.write(src)


#
# now compile the sources
#
SOURCES = [
    'App.elm',
]
with ${...}.swap(RAISE_SUBPROC_ERROR=False):
    HAVE_UGLIFY = bool(!(which uglifyjs e>o))

UGLIFY_FLAGS = ('pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",'
                'pure_getters,keep_fargs=false,unsafe_comps,unsafe')


def compile():
    for source in SOURCES:
        base = os.path.splitext(source.lower())[0]
        src = os.path.join('elm-src', source)
        js_target = os.path.join('js', base + '.js')
        print_color('Compiling {YELLOW}' + src + '{NO_COLOR} -> {GREEN}' +
                    js_target + '{NO_COLOR}')
        $XONSH_SHOW_TRACEBACK = False
        try:
            ![elm make --optimize --output @(js_target) @(src)]
        except Exception:
            import sys
            sys.exit(1)
        new_files = [js_target]
        min_target = os.path.join('js', base + '.min.js')
        if os.path.exists(min_target):
            ![rm -v @(min_target)]
        if HAVE_UGLIFY:
            print_color('Minifying {YELLOW}' + js_target + '{NO_COLOR} -> {GREEN}' +
                        min_target + '{NO_COLOR}')
            ![uglifyjs @(js_target) --compress @(UGLIFY_FLAGS) |
              uglifyjs --mangle --output @(min_target)]
            new_files.append(min_target)
        ![ls -l @(new_files)]


def main():
    write_xonsh_data()
    compile()


if __name__ == "__main__":
    main()