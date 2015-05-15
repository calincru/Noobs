#!/usr/bin/env rdmd
import std.stdio, std.file, std.process, std.string, std.conv, std.algorithm, std.getopt, core.thread,
       std.range, std.exception, std.typecons, std.path, std.random, std.parallelism, std.mathspecial;
enum usage = `
Usage: ./noobs.d bot1 bot2 [--count=<count>]`;


struct settings {
    string map_folder = "warmaps";
    string warengine_folder = "warlight2-engine";
    string warengine_command = `./ng com.theaigames.game.warlight2.Warlight2 "%s" "%s" "%s" "%s"`;
    string nailgun_server_command = `java -Xmx256M -Xms256M -cp nailgun-server-0.9.2-SNAPSHOT.jar:bin:lib/java-json.jar com.martiansoftware.nailgun.NGServer`;
    int count = int.max;
    string bot1;
    string bot2;
}

auto load_settings(string[] args)
{
    settings ret;
    getopt(args, "count", &ret.count);
    if (args.length != 3)
        throw new Exception("Invalid arguments" ~ usage);
    ret.bot1 = args[1];
    ret.bot2 = args[2];
    return ret;
}

void console_back_n_lines(int n)
{
    foreach (_; 0 .. n)
        writef("%c[1A%c[2K", cast(char) 0x1B, cast(char) 0x1B);
}

void main(string[] args)
{
    auto settings = load_settings(args);
    string[] mapfiles;
    try mapfiles = dirEntries(settings.map_folder, SpanMode.shallow).map!"a.name".array;
        catch throw new Exception("Could not open folder " ~ settings.map_folder);
    if (!settings.bot1.exists)
        throw new Exception("File " ~ settings.bot1 ~ " does not exist");
    if (!settings.bot2.exists)
        throw new Exception("File " ~ settings.bot2 ~ " does not exist");

    writeln("Available maps: " ~ mapfiles.length.to!string);

    auto ngserver = pipeShell(settings.nailgun_server_command, Redirect.all,
            null, Config.none, settings.warengine_folder);
    scope(exit) kill(ngserver.pid);
    if (!canFind(ngserver.stdout.byLine.front, "started on all interfaces"))
        throw new Exception(cast(string) ngserver.stderr.byChunk(4096).front);
    Thread.sleep(dur!"msecs"(1500));
    writeln("NGServer started");

    int win1_cnt, game_cnt;
    bool first_time = true;
    writeln();
    foreach (mapfile; taskPool.parallel(mapfiles.take(settings.count), 1))
    {
        int seed = uniform(0, int.max);
        foreach (swap; [false, true])
        {
            auto path1 = absolutePath(settings.bot1);
            auto path2 = absolutePath(settings.bot2);
            auto pathmap = absolutePath(mapfile);
            auto command = settings.warengine_command
                .format(pathmap, swap ? path2 : path1, swap ? path1 : path2, seed);
            auto pipes = pipeShell(command, Redirect.all, null, Config.none, settings.warengine_folder);
            wait(pipes.pid);
            auto command_output = cast(string) pipes.stdout.byChunk(4096).front;
            auto command_err = cast(string) pipes.stderr.byChunk(4096).front;
            if (!canFind(command_output, "winner: "))
                throw new Exception(command_err);

            ++game_cnt;
            if ((canFind(command_output, "winner: player1") && !swap)
                    || (canFind(command_output, "winner: player2") && swap))
                ++win1_cnt;
            auto win2_cnt = game_cnt - win1_cnt;
            if (first_time)
                first_time = false;
            else
                console_back_n_lines(2);
            writefln("1st bot (%s): %s winrate %s/%s", settings.bot1,
                    winrate(win1_cnt, game_cnt), win1_cnt, game_cnt);
            writefln("2nd bot (%s): %s winrate %s/%s", settings.bot2,
                    winrate(win2_cnt, game_cnt), win2_cnt, game_cnt);
        }
    }
}

string winrate(int win, int total) {
    auto ci = binomial_ci(win, total, 0.05);
    if (total == 0)
        return "50.0 (0.0 - 100.0)";
    else
        return "%.1f%% (%.1f - %.1f)".format(100. * win/total, 100. * ci[0], 100. * ci[1]);
};

auto binomial_ci(double k, double n, double err) {
    double z = normalDistributionInverse(1-0.5*err);
    double p = 1.*k/n;
    double coef = 1/(1+(1/n)*z*z);
    double center = coef*(p+1/(2*n)*z*z);
    double offset = coef*z*sqrt(1/n*p*(1-p)+1/(4*n*n)*z*z);
    return tuple(center-offset, center+offset);
}
