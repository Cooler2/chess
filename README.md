# chess
One day in 2009 I decided to write a chess program. Just for fun - to see what can it do.

In March 2021, I accidentally came across these old sources and decided to rewrite and modify them a little.

The key feature of this game is that it uses breadth-first search instead of depth search and keeps the entire search tree in memory. Therefore, it consumes a lot of memory. But this allows to visualize the search tree - this is the most interesting thing, in fact, what I wanted to do it for at all. 

I made it single-threaded: in 2009 I had a 2-core CPU so multithreading won't help me a lot. I also had 2 or 4 GB RAM so didn't suffer from 32-bit memory limit. Anyway, Turbo Delphi Explorer can't build 64-bit program. Now I have 8-core CPU with 16Gb RAM and Delphi Community Edition can build 64-bit programs. That makes some sense in upgrading this game. Let's do this! :-)
