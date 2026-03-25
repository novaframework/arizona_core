-ifndef(ARIZONA_TEST_HRL).
-define(ARIZONA_TEST_HRL, true).

-record(ctx, {
    pid :: pid(),
    view :: arizona_view:view(),
    hierarchical :: arizona_hierarchical_dict:hierarchical_structure(),
    diff :: arizona_differ:diff(),
    actions :: list()
}).

-type ctx() :: #ctx{}.

-define(assertArizonaMatch(Pattern, Ctx),
    ?assert(arizona_test:has_element(Ctx, Pattern))
).

-define(assertArizonaNoMatch(Pattern, Ctx),
    ?assertNot(arizona_test:has_element(Ctx, Pattern))
).

-define(assertArizonaAction(ExpectedAction, Ctx),
    ?assert(
        lists:any(
            fun(A) -> A =:= ExpectedAction end,
            (Ctx)#ctx.actions
        )
    )
).

-endif.
