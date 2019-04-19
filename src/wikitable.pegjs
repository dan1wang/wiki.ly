
/******************************************************************************
 * Tables
 * ------
 * Table rules are geared to support independent parsing of fragments in
 * templates (the common table start / row / table end use case). The tokens
 * produced by these fragments then match up to a table while building the
 * DOM tree. For similar reasons, table rows do not emit explicit end tag
 * tokens.
 *
 * The separate table_line rule is faster than moving those rules
 * directly to block_lines.
 *
 * Notes about the full_table_in_link_caption rule
 * -----------------------------------------------------
 * However, for link-tables, we have introduced a stricter parse wherein
 * we require table-start and table-end tags to not come from a template.
 * In addition, this new rule doesn't accept fosterable-content in
 * the table unlike the more lax (sol table_line)+ rule.
 *
 * This is the best we can do at this time since we cannot distinguish
 * between table rows and image options entirely in the tokenizer.
 *
 * Consider the following examples:
 *
 * Example 1:
 *
 * [[Image:Foo.jpg|left|30px|Example 1
 * {{This-template-returns-a-table-start-tag}}
 * |foo
 * {{This-template-returns-a-table-end-tag}}
 * ]]
 *
 * Example 2:
 *
 * [[Image:Foo.jpg|left|30px|Example 1
 * {{echo|a}}
 * |foo
 * {{echo|b}}
 * ]]
 *
 * So, we cannot know a priori (without preprocessing or fully expanding
 * all templates) if "|foo" in the two examples is a table cell or an image
 * option. This is a limitation of our tokenizer-based approach compared to
 * the preprocessing-based approach of the PHP parser.
 *
 * Given this limitation, we are okay forcing a full-table context in
 * link captions (if necessary, we can relax the fosterable-content requirement
 * but that is broken wikitext anyway, so we can force that edge-case wikitext
 * to get fixed by rejecting it).
 ******************************************************************************/

full_table_in_link_caption
  = (! inline_breaks / & '{{!}}' )
    // Note that "linkdesc" is suppressed here to provide a nested parsing
    // context in which to parse the table.  Otherwise, we may break on
    // on pipes in the `table_start_tag` and `table_row_tag` attributes.
    // However, as a result, this can be more permissive than the current
    // php implementation, but likelier to match the users intent.
    r: full_table_in_link_caption_parameterized<linkdesc=false, table> {
        return r;
    }

full_table_in_link_caption_parameterized
  = tbl:(
        table_start_tag optionalNewlines
        // Accept multiple end tags since a nested table may have been
        // opened in the table content line.
        ((sol (table_content_line / tplarg_or_template) optionalNewlines)*
        sol table_end_tag)+
    ){
        return tbl;
    }

// This rule assumes start-of-line position!
table_line
  = (! inline_breaks / & '{{!}}' )
    tl:(
         table_start_tag optionalNewlines
       / table_content_line<table> optionalNewlines
       / table_end_tag
    ) {
        return tl;
    }

table_content_line = (space / comment)* (
    table_heading_tags
    / table_row_tag
    / table_data_tags
    / table_caption_tag
  )

table_start_tag "table_start_tag"
  = sc:(space / comment)*
    startPos:("" { return endOffset(); })
    b:"{" p:pipe
    // ok to normalize away stray |} on rt (see T59360)
    ta:(table_attributes<table=false> / &{ assert(false); return false; })
    tsEndPos:("" { return endOffset(); })
    s2:space*
    {
        var coms = tu.popComments(ta);
        if (coms) {
          tsEndPos = coms.commentStartPos;
        }

        var da = { tsr: [startPos, tsEndPos] };
        if (p !== "|") {
            // Variation from default
            da.startTagSrc = b + p;
        }

        sc.push(new TagTk('table', ta, da));
        if (coms) {
          sc = sc.concat(coms.buf);
        }
        return sc.concat(s2);
    }

// FIXME: Not sure if we want to support it, but this should allow columns.
table_caption_tag
    // avoid recursion via nested_block_in_table
  = ! <tableDataBlock>
    p:pipe "+"
    args:row_syntax_table_args?
    tagEndPos:("" { return endOffset(); })
    c:nested_block_in_table* {
        return tu.buildTableTokens("caption", "|+", args, [startOffset(), tagEndPos], endOffset(), c, true);
    }

table_row_tag
  = // avoid recursion via nested_block_in_table
    ! <tableDataBlock>
    p:pipe dashes:$"-"+
    a:(table_attributes<table=false> / &{ assert(false); return false; })
    tagEndPos:("" { return endOffset(); })
    {
        var coms = tu.popComments(a);
        if (coms) {
          tagEndPos = coms.commentStartPos;
        }

        var da = {
          tsr: [ startOffset(), tagEndPos ],
          startTagSrc: p + dashes,
        };

        // We rely on our tree builder to close the row as needed. This is
        // needed to support building tables from fragment templates with
        // individual cells or rows.
        var trToken = new TagTk('tr', a, da);

        var res = [ trToken ];
        if (coms) {
          res = res.concat(coms.buf);
        }
        return res;
    }

tds
  = ( pp:( pipe_pipe / p:pipe & row_syntax_table_args { return p; } )
      tdt:table_data_tag {
        // Avoid modifying a cached result
        tdt = tdt.slice();
        tdt[0] = Util.clone(tdt[0]);

        var da = tdt[0].dataAttribs;
        da.stx = "row";
        da.tsr[0] -= pp.length; // include "||"
        if (pp !== "||" || (da.startTagSrc && da.startTagSrc !== pp)) {
          // Variation from default
          da.startTagSrc = pp + (da.startTagSrc ? da.startTagSrc.substring(1) : '');
        }
        return tdt;
      }
    )*

table_data_tags
    // avoid recursion via nested_block_in_table
  = ! <tableDataBlock>
    p:pipe
    ![+-] td:table_data_tag
    tagEndPos:("" { return endOffset(); })
    tds:tds {
        // Avoid modifying a cached result
        td = td.slice();
        td[0] = Util.clone(td[0]);

        var da = td[0].dataAttribs;
        da.tsr[0] -= p.length; // include "|"
        if (p !== "|") {
            // Variation from default
            da.startTagSrc = p;
        }
        return td.concat(tds);
    }

table_data_tag
  = ! "}"
    arg:row_syntax_table_args?
    // use inline_breaks to break on tr etc
    tagEndPos:("" { return endOffset(); })
    td:nested_block_in_table*
    {
        return tu.buildTableTokens("td", "|", arg, [startOffset(), tagEndPos], endOffset(), td);
    }

table_heading_tags = table_heading_tags_parameterized<&th>

table_heading_tags_parameterized
  = "!"
    thTag:table_heading_tag
    thTags:( pp:("!!" / pipe_pipe) tht:table_heading_tag {
            // Avoid modifying a cached result
            tht = tht.slice();
            tht[0] = Util.clone(tht[0]);

            var da = tht[0].dataAttribs;
            da.stx = 'row';
            da.tsr[0] -= pp.length; // include "!!" or "||"

            if (pp !== "!!" || (da.startTagSrc && da.startTagSrc !== pp)) {
                // Variation from default
                da.startTagSrc = pp + (da.startTagSrc ? da.startTagSrc.substring(1) : '');
            }
            return tht;
          }
    )* {
        thTag = thTag.slice();
        thTag[0] = Util.clone(thTag[0]);
        thTag[0].dataAttribs.tsr[0]--; // include "!"
        return thTag.concat(thTags);
    }

table_heading_tag
  = arg:row_syntax_table_args?
    tagEndPos:("" { return endOffset(); })
    c:(
        th:<&th>
        d:nested_block_in_table {
            if (th.get() !== false && /\n/.test(text())) {
                // There's been a newline. Remove the break and continue
                // tokenizing nested_block_in_tables.
                th.set(false);
            }
            return d;
        }
    )* {
        return tu.buildTableTokens("th", "!", arg, [startOffset(), tagEndPos], endOffset(), c);
    }

table_end_tag
  = sc:(space / comment)* startPos:("" { return endOffset(); }) p:pipe b:"}" {
      var tblEnd = new EndTagTk('table', [], { tsr: [startPos, endOffset()] });
      if (p !== "|") {
          // p+"<brace-char>" is triggering some bug in pegJS
          // I cannot even use that expression in the comment!
          tblEnd.dataAttribs.endTagSrc = p + b;
      }
      return sc.concat([tblEnd]);
  }

/**
 * Table parameters separated from the content by a single pipe. Does *not*
 * match if followed by double pipe (row-based syntax).
 */
row_syntax_table_args
  = as:table_attributes<tableCellArg> s:optional_spaces p:pipe !pipe {
        return [as, s, p];
    }
