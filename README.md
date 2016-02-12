# Jira Burndown Chart (Ascii style)

## Overview

Showing a Jira burndown chart that takes in account subtasks. If a story has no subtasks then the points of that story are counted for, if a story has subtask the only the subtasks points are taken into account. If a story or subtask does not have point a warning is displayed.


```
95|
90| *  *
85|
80|       *
75|
70|          *
65|
60|
55|
50|
45|
40|
35|
30|
25|
20|
15|
10|
 5|
 0+------------------------------------
    1  2  3  4  5  6  7  8  9 10 11 12
```

## Install

```$ bundle install```

## Run

```ruby burndown.rb```

Note you must provide your Jira subdomain, the sprint name, username and password.
I.e.

```
Jira subdomain: blinker
Jira sprint name: Sprint 44
Jira username: d@n-so.com
Jira password: secret
```

## To improve

* Don't hard code ```start_date```
* Don't hard code sprint duration
