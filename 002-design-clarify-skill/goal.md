# Goal

## Objective

Draft a design of skill `clarify`.
`clarify` helps user to clarify what they want to achieve.
It asks human questions in dialogue and collects feedback.
It finds unsettled and unclear aspects from human's description and asks more questions.
It settles down the goal that human really wants when it thinks it is clear enough or the human says so.
It asks human for success criteria (what are the artifacts? what regression tests should pass? what new tests should be added? etc.)
It helps human to think through the success criteria (suggest common ones and asks for more).
It asks human for Performance, style, dependency, or safety constraints (suggest common ones and asks for more).
It asks human for non-goals.
It adjust wording to be concise and write down goal.md in a session folder (create one if not already exists) using the goal template.

## Success Criteria

- `draft.md` that can be fed into `creat-skill` skill
- Human's approval

## Constraints

- N/A

## Non-goals

- Create the actual skill.

## Max Rounds

3