use IRC::Client::Plugin;
use DBIish;
use DBDish::SQLite::Connection;

unit class IRC::Client::Plugin::Factoid:ver<1.001001> is IRC::Client::Plugin;

has Regex  $.trigger;
has Bool   $.say-not-found = True;
has Str    $.db-filename   = 'factoids.db';
has DBDish::SQLite::Connection $!dbh;

method irc-start-up ($) {
    my $need-deploy = not $!db-filename.IO.e;
    $!dbh = DBIish.connect: "SQLite", :database($!db-filename), :RaiseError;
    return unless $need-deploy;

    $!dbh.do: q:to/END-SQL/;
        CREATE TABLE factoids (
            id   INTEGER PRIMARY KEY,
            fact TEXT,
            def  TEXT
        );
    END-SQL
}

method irc-privmsg ($irc, $e) {
    return IRC_NOT_HANDLED unless $e<params>[0] ~~ /^ '#&'/;
    my $res = self.handle: $e<params>[1].subst: /^':'/, '';
    return $res if $res === IRC_NOT_HANDLED;
    $irc.respond:
        :where($e<params>[0]),
        :how<privmsg>,
        :what($res);
}

method irc-to-me ($irc, $e, %res) {
    GLOBAL::<IRC::Client::Plugin::Factoid>:delete;
    require IRC::Client::Plugin::Factoid;
    say "Reloaded 23232323!";
    return;

    my $res = self.handle: %res<what>;
    return $res if $res === IRC_NOT_HANDLED;
    $irc.reponse: |%res, :what($res);
}

method handle ($what) {
    return IRC_NOT_HANDLED
        if $!trigger and $what.subst-mutate: $!trigger, '';

    return do given $what {
        when /^ 'purge' \s+ 'factoid' \s+ $<fact>=(.+) \s*/ {
            self!purge-fact: $<fact>;
        }
        when /^ 'delete' \s+ 'factoid' \s+ $<fact>=(.+) \s*/ {
            self!delete-fact: $<fact>;
        }
        when /$<fact>=(.+) \s+ ':is:' \s+ $<def>=(.+)/ {
            self!add-fact: $<fact>, $<def>;
        }
        default { self!find-facts: $_, :1limit; }
    }
}

method !add-fact (Str() $fact, Str() $def) {
    $!dbh.do: 'INSERT INTO factoids (fact, def) VALUES (?,?)', $fact, $def;
    return "Added $fact as $def";
}

method !delete-fact (Str() $fact) {
    return "Didn't find $fact in the database"
        unless self!find-facts: $fact, :1limit;

    self!add-fact: $fact, '';
    return "Marked factoid `$fact` as deleted";
}

method !find-facts (Str() $fact, Int :$limit) {
    my $sth;
    my $sql = 'SELECT id FROM factoids WHERE fact = ? ';
    if $limit {
        $sth = $!dbh.prepare: $sql ~ 'LIMIT ?';
        $sth.execute: $fact, $limit;
    }
    else {
        $sth = $!dbh.prepare: $sql;
        $sth.execute: $fact;
    }
    return $sth.fetchall-array;
}

method !purge-fact (Str() $fact) {
    my @facts = self!find-facts: $fact
        or return "Did not find $fact in the database";

    $!dbh.do: "DELETE FROM factoids WHERE id IN({ join ',', '?' xx @facts })";
    return "Purged factoid `$fact` and its {@facts.elems} edits";
}
