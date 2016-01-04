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

method irc-to-me ($irc, $e, %res) {
    return IRC_NOT_HANDLED
        if $!trigger and %res<what>.subst-mutate: $!trigger, '';

    if %res<what> ~~ /^ 'purge' \s+ 'factoid' \s+ $<fact>=(.+) \s*/ {
        my $fact = ~$<fact>;

        my $sth = $!dbh.prepare('SELECT id FROM factoids WHERE fact = ?');
        $sth.execute($fact);
        my @facts = $sth.fetchall-array;

        return $irc.respond: |%res :what("Did not find $fact in the database")
            unless @facts;

        $!dbh.do: "DELETE FROM factoids WHERE id IN({join ',', '?'xx@facts})";

        return $irc.respond: |%res
            :what("Purged factoid `$fact` and its {@facts.elems} edits");
    }
    elsif %res<what> ~~ /($<fact>=.+) \s+ ':is:' \s+ ($<def>=.+)/ {
        $!dbh.do:
            'INSERT INTO factoids (fact, def) VALUES (?, ?)',
            $<fact>,
            $<def>;

        $irc.respond: |%res, :what("Stored $<fact> as $<def>");
    }

    return IRC_NOT_HANDLED;
}
