# New Topic Checklist

Use this checklist before creating a new thread or automation for a research
topic.

## Topic Contract

- [ ] The folder name is a lowercase hyphenated slug.
- [ ] `topic.md` has a clear goal.
- [ ] Include and exclude scope are both filled in.
- [ ] Priority is set to Low, Medium, or High.
- [ ] Primary and secondary keywords are specific enough to guide research.
- [ ] Source policy says which sources are preferred.
- [ ] "Report When" criteria describe what counts as material.

## Required Files

- [ ] `research/<topic>/topic.md`
- [ ] `research/<topic>/index.md`
- [ ] `research/<topic>/backlog.md`
- [ ] `research/<topic>/runs/`
- [ ] `research/<topic>/proposals/`

## Manual Dry Run

- [ ] Run `$daily-research-agent` manually for the topic.
- [ ] Confirm the report has date, status, scope checked, summary, changes,
      risks, recommended actions, and sources.
- [ ] Confirm source links are present for material claims.
- [ ] Confirm repeated findings are not duplicated from earlier reports.
- [ ] Confirm risky actions are written as proposals.

## Scheduling Gate

- [ ] The manual report is useful enough to review.
- [ ] The backlog has review notes or next actions.
- [ ] The user has approved a dedicated thread and heartbeat automation.
- [ ] The first three scheduled runs will be reviewed manually.
