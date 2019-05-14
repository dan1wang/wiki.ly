/*********************************************************
 *   Lists
 *********************************************************/
list_item = dtdd / hacky_dl_uses / li

li
  = bullets:list_char+
     c:inlineline?
     // The inline_break is to check if we've hit a template end delimiter.
     &(eolf / inline_breaks)
  {
    // Leave bullets as an array -- list handler expects this
    var tsr = tsrOffsets('start');
    tsr[1] += bullets.length;
    var li = new TagTk('listItem', [new KV('bullets', bullets)], { tsr: tsr });
    return [ li ].concat(c || []);
  }

/*
 * This rule is required to support wikitext of this form
 *   ::{|border="1"|foo|bar|baz|}
 * where the leading colons are used to indent the entire table.
 * This hack was added back in 2006 in commit
 * a0746946312b0f1eda30a2c793f5f7052e8e5f3a based on a patch by Carl
 * Fürstenberg.
 */
hacky_dl_uses
  = bullets:":"+
      tbl:(table_line (sol table_line)*)
      line:inlineline?
      &comment_space_eolf
  {
      // Leave bullets as an array -- list handler expects this
      var tsr = tsrOffsets('start');
      tsr[1] += bullets.length;
      var li = new TagTk('listItem', [new KV('bullets', bullets)], { tsr: tsr });
      return tu.flattenIfArray([li, tbl || [], line || []]);
  }

dtdd
  = bullets:(
      !?(";" !list_char)
      list_char
    )*
    ";"
    c:inlineline_break_on_colon?
    cpos:(":" { return endOffset(); })
    d:inlineline?
    &eolf {
        // Leave bullets as an array -- list handler expects this
        // TSR: +1 for the leading ";"
        const numBullets = bullets.length + 1;
        const tsr = tsrOffsets('start');
        tsr[1] += numBullets;
        const li1Bullets = bullets.slice();
        li1Bullets.push(";");
        const li1 = new TagTk('listItem', [new KV('bullets', li1Bullets)], { tsr: tsr });
        // TSR: -1 for the intermediate ":"
        const li2Bullets = bullets.slice();
        li2Bullets.push(":");
        const li2 = new TagTk('listItem', [new KV('bullets', li2Bullets)], { tsr: [cpos - 1, cpos], stx: 'row' });

        return [ li1 ].concat(c || [], [ li2 ], d || []);
    }

list_char = [*#:;]

inlineline_break_on_colon
  = ill:inlineline<colon>
