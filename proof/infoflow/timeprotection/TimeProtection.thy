(*
 * Copyright 2021, UNSW (ABN 57 195 873 179),
 * Copyright 2021, The University of Melbourne (ABN 84 002 705 224).
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *)

theory TimeProtection
imports "Word_Lib.WordSetup"
  InfoFlow.Noninterference_Base
  InfoFlow.Noninterference_Base_Refinement
  Lib.Eisbach_Methods
  "Lib.Apply_Trace_Cmd"
begin

datatype vaddr = VAddr machine_word
datatype paddr = PAddr machine_word

\<comment> \<open> flushable (fch) and partitionable (pch) caches\<close>
type_synonym 'fch_cachedness fch = "vaddr \<Rightarrow> 'fch_cachedness"
type_synonym 'pch_cachedness pch = "paddr \<Rightarrow> 'pch_cachedness"
type_synonym 'fch fch_impact = "vaddr \<Rightarrow> 'fch \<Rightarrow> 'fch"
(* Note: This `pch_impact` version only supports a writethrough `fch`. *)
type_synonym 'pch pch_impact = "paddr \<Rightarrow> 'pch \<Rightarrow> 'pch"
(* FIXME: If we want to support a writeback `fch`, we'll need to use a type signature like this
  instead (note we'll also need to add the page table state as an argument, to get the paddr).
  This is because when a read or write evicts a dirty `fch` entry, that dirty bit (and value)
  will need to be propagated to the corresponding `pch` entry. -robs.
type_synonym ('fch,'pch) pch_impact = "vaddr \<Rightarrow> 'fch \<Rightarrow> 'pch \<Rightarrow> 'pch" *)

type_synonym time = nat

datatype 'userdomain domain = Sched | User 'userdomain

record ('fch,'pch) state =
  fch :: "'fch" \<comment> \<open> flushable cache\<close>
  pch :: "'pch" \<comment> \<open> partitionable cache \<close>
  tm :: time

locale time_protection =
  (* "a coll b" = "a may cause b to be evicted from or loaded to the pch" *)
  fixes collides_in_pch :: "paddr \<Rightarrow> paddr \<Rightarrow> bool" (infix "coll" 50)

  (* collides_in_pch isn't a relation, but it is kind of an equivalence *)
  assumes collides_with_equiv: "equiv UNIV ({(x, y). x coll y})"

  fixes fch_lookup :: "'fch \<Rightarrow> 'fch_cachedness fch"
  fixes pch_lookup :: "'pch \<Rightarrow> 'pch_cachedness pch"

  fixes fch_read_impact :: "'fch fch_impact"
  fixes pch_read_impact :: "'pch pch_impact"

  \<comment> \<open>pch_read_impact only impacts colliding addresses\<close>
  assumes pch_partitioned_read:
    "\<not>a1 coll a2 \<Longrightarrow> pch_lookup p a2 = pch_lookup (pch_read_impact a1 p) a2"


  (* if a2 can be impacted by a read from a1,
     we require that this impact depends only on the prior state of the fch
     and the prior cachedness of the rest of their collision set in the pch *)
  assumes pch_collision_read: "\<And>a1 a2 pchs pcht.
    a1 coll a2 \<Longrightarrow>
    \<forall>a3. a2 coll a3 \<longrightarrow> pch_lookup pchs a3 = pch_lookup pcht a3 \<Longrightarrow>
    \<comment> \<open>This might be stronger than is met by hardware that just promises
        a 'random' replacement algorithm. Essentially we are requiring that
        any such 'randomness' cannot be influenced by the prior cachedness of
        addresses outside the collision set in question. \<close>
    pchs' = pch_read_impact a1 pchs \<Longrightarrow>
    pcht' = pch_read_impact a1 pcht \<Longrightarrow>
    pch_lookup pchs' a2 = pch_lookup pcht' a2"
  

  fixes fch_write_impact :: "'fch fch_impact"
  fixes pch_write_impact :: "'pch pch_impact"

  \<comment> \<open>pch_write_impact only impacts colliding addresses\<close>
  assumes pch_partitioned_write:
    "not (a1 coll a2) \<Longrightarrow> pch_lookup p a2 = pch_lookup (pch_write_impact a1 p) a2"

  
  assumes pch_collision_write: "\<And>a1 a2 pchs pcht. a1 coll a2 \<Longrightarrow>
    \<forall>a3. a2 coll a3 \<longrightarrow> pch_lookup pchs a3 = pch_lookup pcht a3 \<Longrightarrow>
    \<comment> \<open>The same strong requirement placing limits on the 'randomness'
        of the cache replacement algorithm as for @{term pch_collision_read}\<close>
    pchs' = pch_write_impact a1 pchs \<Longrightarrow>
    pcht' = pch_write_impact a1 pcht \<Longrightarrow>
    pch_lookup pchs' a2 = pch_lookup pcht' a2"

  fixes read_cycles  :: "'fch_cachedness \<Rightarrow> 'pch_cachedness \<Rightarrow> time"
  fixes write_cycles :: "'fch_cachedness \<Rightarrow> 'pch_cachedness \<Rightarrow> time"

  fixes empty_fch :: "'fch"
  fixes fch_flush_cycles :: "'fch \<Rightarrow> time" \<comment> \<open>could this be dependent on anything else?\<close>

  fixes do_pch_flush :: "'pch \<Rightarrow> paddr set \<Rightarrow> 'pch"
  fixes pch_flush_cycles :: "'pch \<Rightarrow> paddr set \<Rightarrow> time" \<comment> \<open>could this be dependent on anything else?\<close>


  \<comment> \<open>pch flush only affects addresses that collide with the set\<close>
  assumes pch_partitioned_flush:
   "(\<forall>a'\<in>as. \<not> a coll a') \<Longrightarrow> pch_lookup (do_pch_flush p as) a = pch_lookup p a"

  (* again, just trying to see if we can get away without this - Scott B
  assumes pch_collision_flush:
    "\<exists>a1\<in>as. a coll a1 \<Longrightarrow>
    \<forall>a1. (\<exists>a2\<in>as. a1 coll a2) \<longrightarrow> pch_lookup pchs a1 = pch_lookup pcht a1 \<Longrightarrow>
    pch_lookup (do_pch_flush pchs as) a = pch_lookup (do_pch_flush pcht as) a"
  *)

  \<comment> \<open> if all colliding addresses to @{term as} are the same, then the flush will take the same amount of time \<close>
  assumes pch_flush_cycles_localised:
    "\<forall>a1. (\<exists>a2\<in>as. a1 coll a2) \<longrightarrow> pch_lookup pchs a1 = pch_lookup pcht a1 \<Longrightarrow>
    pch_flush_cycles pchs as = pch_flush_cycles pcht as"

  \<comment> \<open>for each address, this is the security domain\<close>
  fixes addr_domain :: "paddr \<Rightarrow> 'userdomain domain"

  \<comment> \<open>for each address, this is the cache colour\<close>
  fixes addr_colour :: "paddr \<Rightarrow> 'colour"

  fixes colour_userdomain :: "'colour \<Rightarrow> 'userdomain"

  assumes no_cross_colour_collisions:
    "a1 coll a2 \<Longrightarrow> addr_colour a1 = addr_colour a2"
  assumes addr_domain_valid: "addr_domain a = Sched
                            \<or> addr_domain a = User (colour_userdomain (addr_colour a))"
\<comment> \<open>do we assert this here
  or just put it in the type so it has to be asserted before instantiation? or assert it differently
  later?\<close>


  fixes current_domain :: "'other_state \<Rightarrow> 'userdomain domain"
  fixes external_uwr :: "'userdomain domain \<Rightarrow> ('other_state \<times> 'other_state) set"
  assumes external_uwr_equiv_rel:
    "equiv UNIV (external_uwr d)"
  (* The parent locale requires current_domain to be equated by Sched uwr, which confidentiality_u
     then treats as specifying public information; assuming that it is instead equated by every
     domain's uwr arguably simplifies things without changing the strength of the property.
       Without this assumption, I expect we'll need to add the Sched uwr explicitly to the
     pre-equivalence of many lemmas; it may also be a bit harder to prove that our uwr is an
     equivalence relation without it. It may be reasonable to keep this if it holds (or can
     reasonably be made to hold) for the seL4 infoflow theory's unwinding relation. -robs. *)
  assumes external_uwr_same_domain:
    "(s1, s2) \<in> external_uwr d \<Longrightarrow> current_domain s2 = current_domain s1"
\<comment> \<open>we will probably needs lots more info about this external uwr\<close>

  (*TODO: is this a good way to do this? or should we carry around Sched uwr all the time separately? *)
  assumes external_uwr_Sched:
    "(s, t) \<in> external_uwr d \<Longrightarrow> (s, t) \<in> external_uwr Sched"

  (* This is an abstraction for the page table. -robs *)
  fixes v_to_p :: "'other_state \<Rightarrow> vaddr \<Rightarrow> paddr"
  assumes external_uwr_current_page_table:
    "(s, t) \<in> external_uwr d \<Longrightarrow> current_domain s = d \<Longrightarrow> v_to_p t = v_to_p s"

  fixes touched_addrs :: "'other_state \<Rightarrow> vaddr set"
  assumes external_uwr_same_touched_addrs:
    "(s1, s2) \<in> external_uwr d \<Longrightarrow> current_domain s1 = d \<Longrightarrow> touched_addrs s1 = touched_addrs s2"

  (* We expect this to be true for, say, seL4's KSched \<rightarrow> KExit step. -robs. *)
  fixes will_domain_switch :: "'other_state \<Rightarrow> bool"
  assumes will_domain_switch_public:
    "(os, ot) \<in> external_uwr d \<Longrightarrow> will_domain_switch ot = will_domain_switch os"
begin

corollary colours_not_shared:
  "colour_userdomain c1 \<noteq> colour_userdomain c2 \<Longrightarrow> c1 \<noteq> c2"
  by blast

definition all_paddrs_of :: "'userdomain domain \<Rightarrow> paddr set" where
  "all_paddrs_of d = {a. addr_domain a = d}"

abbreviation collision_set :: "paddr \<Rightarrow> paddr set" where
  "collision_set a \<equiv> {b. a coll b}"

lemma collision_set_contains_itself: "a \<in> collision_set a"
  using collides_with_equiv
  by (clarsimp simp:equiv_def refl_on_def)

lemma external_uwr_refl [simp]:
  "(s, s) \<in> external_uwr d"
  using external_uwr_equiv_rel
  by (clarsimp simp: equiv_def refl_on_def)

lemma collision_collect:
  "a coll b = ((a, b) \<in> (Collect (case_prod collides_in_pch)))"
  by simp

lemma collision_sym [simp]:
  "a coll b \<Longrightarrow> b coll a"
  using collision_collect
  by (meson collides_with_equiv equiv_def symE)

\<comment> \<open> the addresses in kernel shared memory (which for now is everything in the sched domain)\<close>
definition kernel_shared_precise :: "paddr set" where
  "kernel_shared_precise \<equiv> {a. addr_domain a = Sched}"

\<comment> \<open> the kernel shared memory, including cache colliding addresses \<close>
definition kernel_shared_expanded :: "paddr set" where
  "kernel_shared_expanded \<equiv> {a. \<exists> z \<in> kernel_shared_precise. a \<in> collision_set z}"

\<comment> \<open> a full collision set contains all of its own collisions \<close>
definition full_collision_set :: "paddr set \<Rightarrow> bool" where
  "full_collision_set S \<equiv> \<forall>a1\<in>S. \<forall>a2. a1 coll a2 \<longrightarrow> a2 \<in> S"

lemma collision_set_full_collision_set:
  "full_collision_set (collision_set a)"
  apply (clarsimp simp: full_collision_set_def)
  using collision_collect
  apply (meson collides_with_equiv equiv_def trans_def)
  done

lemma kernel_shared_expanded_full_collision_set:
  "full_collision_set kernel_shared_expanded"
  apply (clarsimp simp: kernel_shared_expanded_def full_collision_set_def)
  using collision_collect
  apply (meson collides_with_equiv equiv_def trans_def)
  done

\<comment> \<open> in a full collision set S, if two addresses collide and one is not in the set, the other
     is also not in the set. \<close>
lemma collision_in_full_collision_set:
  "full_collision_set S \<Longrightarrow>
  a1 coll a2 \<Longrightarrow>
  a1 \<notin> S \<Longrightarrow>
  a2 \<notin> S"
  apply (clarsimp simp: full_collision_set_def)
  done

definition paddrs_of ::
  "'other_state \<Rightarrow> vaddr set \<Rightarrow> paddr set"
  where
  "paddrs_of s vas \<equiv> {a. \<exists>v. a = v_to_p s v \<and> v \<in> vas}"

definition touched_paddrs ::
  "'other_state \<Rightarrow> paddr set"
  where
  "touched_paddrs s \<equiv> paddrs_of s (touched_addrs s)"

(*FIXME: Move these? These seem more of an IF framework thing. -Scott B *)
\<comment> \<open> the invariant that touched_addresses is always sensible for its current domain \<close>
definition touched_addrs_inv :: "'other_state \<Rightarrow> bool" where
  "touched_addrs_inv s \<equiv>
     touched_paddrs s \<subseteq> all_paddrs_of (current_domain s) \<union> kernel_shared_precise"

(* this isn't true apparently?
definition page_table_inv :: "'other_state \<Rightarrow> bool" where
  "page_table_inv s \<equiv>
     \<forall> a. v_to_p s a \<in> all_paddrs_of (current_domain s) \<union> kernel_shared_precise"
*)



definition pch_same_for_domain ::
  "'userdomain domain \<Rightarrow> 'pch \<Rightarrow> 'pch \<Rightarrow> bool"
  where
 "pch_same_for_domain d p1 p2 \<equiv> \<forall> a. addr_domain a = d \<longrightarrow> pch_lookup p1 a = pch_lookup p2 a"

definition pch_same_for_domain_and_shared ::
  "'userdomain domain \<Rightarrow> 'pch \<Rightarrow> 'pch \<Rightarrow> bool"
  where
 "pch_same_for_domain_and_shared d p1 p2 \<equiv>
    \<forall> a. addr_domain a = d \<or> a \<in> kernel_shared_expanded \<longrightarrow> pch_lookup p1 a = pch_lookup p2 a"

definition pch_same_for_domain_except_shared ::
  "'userdomain domain \<Rightarrow> 'pch \<Rightarrow> 'pch \<Rightarrow> bool"
  where
 "pch_same_for_domain_except_shared d p1 p2 \<equiv>
    \<forall> a. addr_domain a = d \<and> a \<notin> kernel_shared_expanded \<longrightarrow> pch_lookup p1 a = pch_lookup p2 a"

definition uwr_running ::
  "'userdomain domain \<Rightarrow> ('fch,'pch)state rel"
  where
  "uwr_running d \<equiv> {(s1, s2). fch s1 = fch s2
                            \<and> pch_same_for_domain_and_shared d (pch s1) (pch s2)
                            \<and> tm s1 = tm s2 }"

definition uwr_notrunning ::
  "'userdomain domain \<Rightarrow> ('fch,'pch)state rel"
  where
  "uwr_notrunning d \<equiv> {(s1, s2). pch_same_for_domain_except_shared d (pch s1) (pch s2) }"

definition uwr ::
  "'userdomain domain \<Rightarrow> ('other_state \<times> ('fch,'pch)state) rel"
  where
  "uwr d \<equiv> {((os1, s1), (os2, s2)). (os1, os2) \<in> external_uwr d \<and>
                      (if (current_domain os1 = d)
                      then (s1, s2) \<in> uwr_running d
                      else (s1, s2) \<in> uwr_notrunning d ) }"

lemma uwr_external_uwr:
  "((so, s), (to, t)) \<in> uwr d \<Longrightarrow>
  (so, to) \<in> external_uwr d"
  apply (clarsimp simp: uwr_def)
  done

(*
lemma uwr_to_external:
  "(s, t) \<in> uwr d \<Longrightarrow> (other_state s, other_state t) \<in> external_uwr d"
  by (clarsimp simp:uwr_def uwr_running_def uwr_notrunning_def split:if_splits)

lemma uwr_same_domain:
  "(s, t) \<in> uwr d \<Longrightarrow> current_domain' s = current_domain' t"
  by (force dest:uwr_to_external external_uwr_same_domain)

lemma uwr_same_touched_addrs:
  "(s, t) \<in> uwr d \<Longrightarrow> current_domain' s = d \<Longrightarrow> touched_addrs' s = touched_addrs' t"
  by (force dest:uwr_to_external external_uwr_same_touched_addrs)
*)

lemma uwr_refl [simp]:
  "(s, s) \<in> uwr d"
  apply (clarsimp simp:uwr_def)
  apply (clarsimp simp: uwr_running_def pch_same_for_domain_and_shared_def)
  apply (clarsimp simp:uwr_notrunning_def pch_same_for_domain_except_shared_def)
  done

lemma uwr_sym':
  "((a, b) \<in> uwr d) \<Longrightarrow> ((b, a) \<in> uwr d)"
  apply (clarsimp simp: uwr_def)
  apply (frule external_uwr_same_domain; clarsimp)
  apply (case_tac "current_domain os2 = d"; clarsimp)
   apply (intro conjI, meson equiv_def external_uwr_equiv_rel symE)
   apply (clarsimp simp:uwr_running_def pch_same_for_domain_and_shared_def)
  apply (intro conjI, meson equiv_def external_uwr_equiv_rel symE)
  apply (clarsimp simp: uwr_notrunning_def pch_same_for_domain_except_shared_def)
  done

lemma uwr_trans:
  "(a, b) \<in> uwr d \<Longrightarrow>
  (b, c) \<in> uwr d \<Longrightarrow>
  (a, c) \<in> uwr d"
  apply (clarsimp simp: uwr_def)
  apply (frule external_uwr_same_domain; clarsimp)
  apply (case_tac "current_domain x = d"; clarsimp)
   apply (intro conjI, meson equiv_def external_uwr_equiv_rel transE)
   apply (clarsimp simp:uwr_running_def pch_same_for_domain_and_shared_def)
  apply (intro conjI, meson equiv_def external_uwr_equiv_rel transE)
  apply (clarsimp simp: uwr_notrunning_def pch_same_for_domain_except_shared_def)
  done

lemma uwr_equiv_rel:
  "equiv UNIV (uwr u)"
  apply(clarsimp simp:equiv_def)
  apply(intro conjI)
    \<comment> \<open>refl\<close>
    apply (clarsimp simp: refl_on_def)
   \<comment> \<open>sym\<close>
   apply (clarsimp simp:sym_def, erule uwr_sym')
  \<comment> \<open>trans\<close>
  apply (clarsimp simp:trans_def, erule uwr_trans, simp)
  done


(* notes about confidentiality properties with this model:
   
  for some step (let's say the user step for example), for a step of the NOT CURRENTLY RUNNING
  domain d:
  - we have two programs derived from touched_addresses - may not be the same touched_addresses (? ? ?)
    - we may not have concrete touched_addresses-es - we may overapprox this to the whole currently running domain
  - these touched_addresses does NOT contain any addresses from d
  - initial states s and t hold uwr_notrunning
  - we execute both programs
  - new state s' and t' hold uwr_notrunning
  - this will rely on infoflow properties of external_uwr

  ...and for a step of the CURRENTLY RUNNING domain d:
  - we have two programs derived from the same touched_addresses
    - these have to be the same program (so we need to know that the choice depends on stuff in
      other_state in the external uwr)
  - that touched_addresses ONLY contains addresses in d
  - initial states s and t hold uwr_running
  - we execute the program on both states
  - new states s' and t' hold uwr_running
  - this will rely on infoflow properties of external_uwr
  
  


*)






(* now we make some basic instructions, which contain addresses etc *)
datatype instr = IRead vaddr            \<comment> \<open>read from some address\<close>
               | IWrite vaddr           \<comment> \<open>write to some address\<close>
               | IFlushL1               \<comment> \<open>flush the entire L1 cache(s)\<close>
               | IFlushL2 "paddr set"   \<comment> \<open>flush some part L2 cache(s)\<close>
               | IPadToTime time        \<comment> \<open>pad the time up to some point\<close>

primrec
  instr_step :: "instr \<Rightarrow>
    'other_state \<Rightarrow>
    ('fch,'pch)state \<Rightarrow>
    ('fch,'pch)state" where
 "instr_step (IRead a) os s =
      s\<lparr>fch := fch_read_impact a (fch s),
        pch := pch_read_impact (v_to_p os a) (pch s),
        tm  := tm s + read_cycles (fch_lookup (fch s) a) (pch_lookup (pch s) (v_to_p os a))\<rparr>"
  | "instr_step (IWrite a) os s =
      s\<lparr>fch := fch_write_impact a (fch s),
        pch := pch_write_impact (v_to_p os a) (pch s),
        tm  := tm s + write_cycles (fch_lookup (fch s) a) (pch_lookup (pch s) (v_to_p os a))\<rparr>"
  | "instr_step (IPadToTime t) _ s =
      s\<lparr>tm := t\<rparr>"
  | "instr_step IFlushL1 _ s =
      s\<lparr>fch := empty_fch,
        tm := tm s + fch_flush_cycles (fch s)\<rparr>"
  | "instr_step (IFlushL2 as) _ s =
      s\<lparr>pch := do_pch_flush (pch s) as,
        tm := tm s + pch_flush_cycles (pch s) as\<rparr>"

type_synonym program = "instr list"

primrec instr_multistep :: "program \<Rightarrow>
  'other_state \<Rightarrow>
  ('fch,'pch)state \<Rightarrow>
  ('fch,'pch)state" where
  "instr_multistep [] os s = s"
| "instr_multistep (i#is) os s = instr_multistep is os (instr_step i os s)"

definition
  instrs_obeying_ta :: "'other_state \<Rightarrow> instr set" where
 "instrs_obeying_ta s \<equiv> {i. case i of
                            IRead a  \<Rightarrow> a \<in> touched_addrs s
                          | IWrite a \<Rightarrow> a \<in> touched_addrs s
                          | IFlushL2 as \<Rightarrow> as \<subseteq> touched_paddrs s
                          | _        \<Rightarrow> True }"

definition
  instrs_obeying_set :: "'other_state \<Rightarrow> paddr set \<Rightarrow> instr set" where
 "instrs_obeying_set s pas \<equiv> {i. case i of
                            IRead a  \<Rightarrow> v_to_p s a \<in> pas
                          | IWrite a \<Rightarrow> v_to_p s a \<in> pas
                          | IFlushL2 as \<Rightarrow> as \<subseteq> pas
                          | _        \<Rightarrow> True }"

(* these are the programs that could have created this ta *)
definition
  programs_obeying_ta :: "'other_state \<Rightarrow> program set" where
 "programs_obeying_ta s \<equiv> {p. list_all (\<lambda>i. i \<in> instrs_obeying_ta s) p}"

(* these are the programs that could have created this ta *)
definition
  programs_obeying_set :: "'other_state \<Rightarrow> paddr set \<Rightarrow> program set" where
 "programs_obeying_set s pas \<equiv> {p. list_all (\<lambda>i. i \<in> instrs_obeying_set s pas) p}"

lemma hd_instr_obeying_ta [dest]:
  "a # p \<in> programs_obeying_ta ta \<Longrightarrow> a \<in> instrs_obeying_ta ta"
  by (force simp:programs_obeying_ta_def)

(*
definition is_secure_nondomainswitch ::
  "'regs program \<Rightarrow> ('fch,'pch,'regs,'other_state)state \<Rightarrow> bool"
  where
  "is_secure_nondomainswitch p s \<equiv>
      \<comment> \<open>Oblige the original system not to reach any system-step that would require either
          (1) straying out of touched_addresses or (2) switching domains to implement.\<close>
      p \<in> programs_obeying_ta (other_state s)"
*)








(* question: for the dirty program in domainswitch, how does the kernel address stuff in 
   the other domain? does v_to_p capture that? does the kernel have its own v_to_p? *)

type_synonym ('os, 'ud) dirty_program_getter = "'ud domain \<Rightarrow> 'ud domain \<Rightarrow> 'os \<Rightarrow> program"

type_synonym 'os next_time_getter = "'os \<Rightarrow> time"

definition same_next_time :: "'other_state next_time_getter \<Rightarrow> bool" where
  "same_next_time ntg \<equiv> \<forall> os os'. ((os, os') \<in> external_uwr Sched \<longrightarrow> ntg os' = ntg os)"

definition same_dirty_programs :: " ('other_state, 'userdomain) dirty_program_getter \<Rightarrow> bool" where
  "same_dirty_programs dpg \<equiv> \<forall> u v os os'. ((os, os') \<in> external_uwr Sched \<longrightarrow> dpg u v os' = dpg u v os)"

(*TODO: currently we have an issue of potentially disagreeing page tables here *)
(* this assumes that `os`'s v_to_p maps to physical addresses belonging to BOTH users *)
definition correct_dirty_programs :: " ('other_state, 'userdomain) dirty_program_getter \<Rightarrow> bool" where
  "correct_dirty_programs dpg \<equiv> \<forall> u v os. dpg u v os \<in> programs_obeying_set os (all_paddrs_of u \<union> all_paddrs_of v \<union> kernel_shared_precise)"

(* sketching out some definitions for domain-switch programs -scott *)
(* TODO: we need to deal with WCETs, and/or make it so that IPadToTime can't go backwards, which will force
   the proofs to deal with WCETs *)
definition get_domain_switch_program ::
  "('other_state, 'userdomain) dirty_program_getter \<Rightarrow> 'other_state next_time_getter \<Rightarrow> 'userdomain domain \<Rightarrow> 'userdomain domain \<Rightarrow> 'other_state \<Rightarrow> program"
  where
  "get_domain_switch_program dpg ntg u v os \<equiv> dpg u v os @ [IFlushL1, IFlushL2 kernel_shared_precise, IPadToTime (ntg os)]"


lemma collides_with_set_or_doesnt:
  "\<lbrakk>\<forall>a'\<in>as. \<not> a coll a' \<Longrightarrow> P;
    \<exists>a'\<in>as. a coll a' \<Longrightarrow> P \<rbrakk> \<Longrightarrow>
    P"
  by blast

lemma diff_domain_no_collision:
  "\<lbrakk>a \<notin> kernel_shared_expanded;
  addr_domain a' \<noteq> addr_domain a;
  a coll a'\<rbrakk> \<Longrightarrow>
  False"
  apply (frule(1) collision_in_full_collision_set [OF kernel_shared_expanded_full_collision_set])
  apply (metis (mono_tags, lifting) addr_domain_valid collision_set_contains_itself
               kernel_shared_expanded_def kernel_shared_precise_def mem_Collect_eq
               no_cross_colour_collisions)
  done

lemma in_inter_empty:
  "\<lbrakk>x \<in> S1;
  S1 \<inter> S2 = {} \<rbrakk> \<Longrightarrow>
  x \<notin> S2"
  by blast

lemma in_sub_inter_empty:
  "\<lbrakk>x \<in> S1;
  S1 \<subseteq> S2;
  S2 \<inter> S3 = {} \<rbrakk> \<Longrightarrow>
  x \<notin> S3"
  by blast

lemma in_sub_union:
  "\<lbrakk>x \<in> S1;
  S1 \<subseteq> S2;
  S2 \<subseteq> S3 \<union> S4\<rbrakk> \<Longrightarrow>
  x \<in> S3 \<or> x \<in> S4"
  by blast

(* this helps avoid/reverse some unhelpful clarsimp behaviour *)
lemma and_or_specific:
  "(\<And>x. (P x \<or> Q x \<Longrightarrow> R x)) \<Longrightarrow>
   \<forall>a. (P a \<longrightarrow> R a) \<and> (Q a \<longrightarrow> R a)"
  apply blast
  done

(*
lemma d_not_running_step:
  assumes
  "i \<in> instrs_obeying_ta os"
  "touched_addrs_inv os"
  "current_domain os \<noteq> d"
  "s' = instr_step i s"
  shows
  "((os, s), (os, s')) \<in> uwr d"
*)

lemma in_touched_addrs_in_touched_paddrs:
  "a \<in> touched_addrs os \<Longrightarrow>
   v_to_p os a \<in> touched_paddrs os"
  using paddrs_of_def touched_paddrs_def apply auto
  done

lemma in_touched_addrs_expand:
  "a \<in> touched_addrs os \<Longrightarrow>
  touched_addrs_inv os \<Longrightarrow>
  v_to_p os a \<in> all_paddrs_of (current_domain os) \<or> v_to_p os a \<in> kernel_shared_precise"
  apply (drule in_touched_addrs_in_touched_paddrs)
  apply (clarsimp simp:touched_addrs_inv_def)
  apply (drule(1) subsetD, subst (asm) Un_iff)
  apply clarsimp
  done


lemma d_running_step:
  assumes
    "i \<in> instrs_obeying_ta os'"
    "touched_addrs_inv os'"
    "((os, s), (ot, t)) \<in> uwr d"
    "(os, ot) \<in> external_uwr d"
    "(os', ot') \<in> external_uwr d"
    "current_domain os = d"
    "s' = instr_step i os s"
    "t' = instr_step i ot t"
    (* the only thing we care about output other_state is that the domain hasn't changed *)
    "current_domain os' = current_domain os"
    "current_domain ot' = current_domain ot"
  shows
    "((os', s'), (ot', t')) \<in> uwr d"
  proof (cases i)
    case (IRead a)
    thus ?thesis using assms
      apply (clarsimp simp: uwr_def uwr_running_def instrs_obeying_ta_def)
      apply (thin_tac "s' = _", thin_tac "t' = _")
      apply (frule external_uwr_current_page_table, simp)
      apply clarsimp
      apply (intro conjI)
       (* pch *)
       apply (drule(1) in_touched_addrs_expand)
       apply (clarsimp simp: touched_addrs_inv_def)
       apply (clarsimp simp: pch_same_for_domain_and_shared_def)


       apply (clarsimp simp: touched_addrs_inv_def all_paddrs_of_def)
       apply(frule external_uwr_current_page_table[symmetric])
        apply force
       
       apply (clarsimp simp: touched_paddrs_def paddrs_of_def)
      (*
      (* apply(clarsimp simp:page_table_inv_def) *)
      (* First obtain that `a` belongs to the current domain or shared memory (i.e. Sched) *)
      apply(clarsimp simp:all_paddrs_of_def)
      apply(erule_tac x=a in allE)
      apply(erule_tac c="v_to_p' s a" in subsetCE)
       apply(force simp:touched_paddrs_def paddrs_of_def)
*)


  oops

(*
  proof (cases i)
    case (IRead a)
    thus ?thesis using assms
      apply(clarsimp simp:uwr_def uwr_running_def)
      apply(clarsimp simp:instrs_obeying_ta_def touched_addrs_inv_def)
      apply(frule external_uwr_current_page_table[symmetric])
       apply force
      apply(clarsimp simp:page_table_inv_def)
      (* First obtain that `a` belongs to the current domain or shared memory (i.e. Sched) *)
      apply(clarsimp simp:all_paddrs_of_def)
      apply(erule_tac x=a in allE)
      apply(erule_tac c="v_to_p' s a" in subsetCE)
       apply(force simp:touched_paddrs_def paddrs_of_def)
      apply clarsimp
      apply(rule conjI)
       (* equivalence on part of pch *)
       apply(clarsimp simp:pch_same_for_domain_and_shared_def kernel_shared_expanded_def)
       apply(rename_tac a')
       apply(case_tac "a' \<in> collision_set (v_to_p' s a)")
        (* for colliding addresses *)
        apply clarsimp
        apply(rule conjI)
         apply clarsimp
         apply(rule pch_collision_read[where pchs="pch s" and pcht="pch t" and ?a1.0="v_to_p' s a"])
            apply force
           apply(metis (mono_tags, lifting) addr_domain_valid collision_set_contains_itself kernel_shared_precise_def mem_Collect_eq no_cross_colour_collisions)
          apply force
         apply force
        apply clarsimp
        apply(rule pch_collision_read[where pchs="pch s" and pcht="pch t" and ?a1.0="v_to_p' s a"])
           apply force
          apply(metis collision_in_full_collision_set collision_set_contains_itself collision_set_full_collision_set mem_Collect_eq)
         apply force
        apply force
       apply clarsimp
       (* for non-colliding addresses *)
       using pch_partitioned_read
       apply metis
      apply(rule conjI)
       (* equivalence of read cycles *)
       apply(erule disjE)
        apply(force simp:pch_same_for_domain_and_shared_def)
       apply(clarsimp simp:pch_same_for_domain_and_shared_def kernel_shared_expanded_def)
       using collision_set_contains_itself
       apply fastforce
      apply (erule disjE)
       (* equivalence of what is read from external state, from external uwr *)
       apply (erule(1) do_read_from_external_uwr_domain)
       apply force
      (* equivalence of what is read from kernel shared memory *)
      apply (erule do_read_from_external_uwr_sched)
       apply (clarsimp simp: kernel_shared_precise_def)
      apply force
      done
  next
    case (IWrite a)
    (* NB: Reasoning is mostly identical to that for IRead -robs. *)
    thus ?thesis using assms
      apply(clarsimp simp:uwr_def uwr_running_def)
      apply(clarsimp simp:instrs_obeying_ta_def touched_addrs_inv_def)
      apply(frule external_uwr_current_page_table[symmetric])
       apply force
      apply(clarsimp simp:page_table_inv_def)
      (* First obtain that `a` belongs to the current domain or shared memory (i.e. Sched) *)
      apply(clarsimp simp:all_paddrs_of_def)
      apply(erule_tac x=a in allE)
      apply(erule_tac c="v_to_p' s a" in subsetCE)
       apply(force simp:touched_paddrs_def paddrs_of_def)
      apply clarsimp
      apply(rule conjI)
       (* equivalence on part of pch *)
       apply(clarsimp simp:pch_same_for_domain_and_shared_def kernel_shared_expanded_def)
       apply(rename_tac a')
       apply(case_tac "a' \<in> collision_set (v_to_p' s a)")
        (* for colliding addresses *)
        apply clarsimp
        apply(rule conjI)
         apply clarsimp
         apply(rule pch_collision_write[where pchs="pch s" and pcht="pch t" and ?a1.0="v_to_p' s a"])
            apply force
           apply(metis (mono_tags, lifting) addr_domain_valid collision_set_contains_itself kernel_shared_precise_def mem_Collect_eq no_cross_colour_collisions)
          apply force
         apply force
        apply clarsimp
        apply(rule pch_collision_write[where pchs="pch s" and pcht="pch t" and ?a1.0="v_to_p' s a"])
           apply force
          apply(metis collision_in_full_collision_set collision_set_contains_itself collision_set_full_collision_set mem_Collect_eq)
         apply force
        apply force
       apply clarsimp
       (* for non-colliding addresses *)
       using pch_partitioned_write
       apply metis
      apply(rule conjI)
       (* equivalence of write cycles *)
       apply(erule disjE)
        apply(force simp:pch_same_for_domain_and_shared_def)
       apply(clarsimp simp:pch_same_for_domain_and_shared_def kernel_shared_expanded_def)
       using collision_set_contains_itself
       apply fastforce
      (* equivalence of the written impact on regs *)
      apply (erule disjE)
       (* equivalence of what is read from external state, from external uwr *)
       apply (erule(1) do_write_from_external_uwr_domain)
       apply force
      (* equivalence of what is read from kernel shared memory *)
      apply (erule do_write_from_external_uwr_sched)
       apply (clarsimp simp: kernel_shared_precise_def)
      apply force
      done
  next
    case (IRegs x3)
    thus ?thesis using assms by (force simp:uwr_def uwr_running_def)
  next
    case IFlushL1
    thus ?thesis using assms by (force simp:uwr_def uwr_running_def)
  next
    case (IFlushL2 fa)
    then show ?thesis using assms
      apply (clarsimp simp: uwr_def uwr_running_def pch_same_for_domain_and_shared_def
                            instrs_obeying_ta_def)
      apply (thin_tac "s' = _", thin_tac "t' = _") (* messy and not needed *)
      apply (subgoal_tac "\<forall>a1. (\<exists>a2\<in>fa. (a1, a2) \<in> collides_in_pch) \<longrightarrow> pch_lookup (pch s) a1 = pch_lookup (pch t) a1")
       defer
        apply clarsimp
        apply (drule_tac x=a1 in spec)
        apply clarsimp
        (* Adapted from an Isar proof found by Sledgehammer -robs. *)
        apply(prop_tac "full_collision_set {p. \<exists>pa. pa \<in> kernel_shared_precise \<and> p \<in> collision_set pa}")
         apply(metis (no_types) kernel_shared_expanded_def kernel_shared_expanded_full_collision_set)
        apply(prop_tac "fa \<subseteq> {v_to_p' s v |v. v \<in> touched_addrs' s}")
         apply(force simp:touched_paddrs_def paddrs_of_def)
        apply(prop_tac "addr_domain a2 \<noteq> current_domain' s")
         apply(metis (no_types) diff_domain_no_collision)
        apply(prop_tac "addr_domain a2 = Sched")
         using all_paddrs_of_def kernel_shared_precise_def touched_addrs_inv_def
         apply blast
        apply(prop_tac "addr_domain a1 = Sched")
         apply(metis diff_domain_no_collision)
        using collision_in_full_collision_set kernel_shared_expanded_def kernel_shared_precise_def
        apply blast
      apply (intro conjI)
       (* pch flush affects are partitioned or deterministic on collision *)
       apply (rule and_or_specific)
       apply (rename_tac a)
       apply (rule_tac a=a and as=fa in collides_with_set_or_doesnt)
        (* a has no collision with fa *)
        apply (frule pch_partitioned_flush [where p = "pch s"])
        apply (frule pch_partitioned_flush [where p = "pch t"])
        apply (clarsimp, blast)
       (* a collides with fa *)
       apply (erule(1) pch_collision_flush)
      (* pch flush cycles depend only on equiv state *)
      apply (erule pch_flush_cycles_localised)
      done
  next
    case IReadTime
    thus ?thesis using assms by (force simp:uwr_def uwr_running_def)
  next
    case (IPadToTime x7)
    thus ?thesis using assms by (force simp:uwr_def uwr_running_def)
  qed *)

(*
lemma touched_addrs_inv_preserved:
  "\<lbrakk>touched_addrs_inv' s; page_table_inv' s;
    s' = instr_multistep p (instr_step a s);
    current_domain' (instr_step a s) = current_domain' s;
    a \<in> instrs_safe (other_state s)\<rbrakk>
   \<Longrightarrow> touched_addrs_inv' (instr_step a s)"
  apply(clarsimp simp:instrs_obeying_ta_def
    programs_safe_def instrs_safe_def list_all_def split:instr.splits)
   using page_table_inv_def page_table_not_in_mem touched_addrs_inv_def touched_paddrs_def paddrs_of_def
   apply(force simp add: touched_addrs_not_in_mem)
  done

lemma touched_addrs_inv_preserved':
  "\<lbrakk>a # p \<in> programs_obeying_ta (other_state s); a # p \<in> programs_safe (other_state s);
    touched_addrs_inv' s; page_table_inv' s; (s, t) \<in> uwr (current_domain' s);
    s' = instr_multistep p (instr_step a s); t' = instr_multistep p (instr_step a t);
    d = current_domain' s; current_domain' (instr_step a s) = d\<rbrakk>
   \<Longrightarrow> touched_addrs_inv' (instr_step a s)"
  apply(clarsimp simp:programs_obeying_ta_def programs_safe_def)
  using touched_addrs_inv_preserved by blast

lemma page_table_inv_preserved:
  "\<lbrakk>touched_addrs_inv' s; page_table_inv' s;
    s' = instr_multistep p (instr_step a s);
    current_domain' (instr_step a s) = current_domain' s;
    a \<in> instrs_safe (other_state s)\<rbrakk>
   \<Longrightarrow> page_table_inv' (instr_step a s)"
  apply(clarsimp simp:programs_obeying_ta_def instrs_obeying_ta_def
    programs_safe_def instrs_safe_def list_all_def split:instr.splits)
   using page_table_inv_def page_table_not_in_mem touched_addrs_inv_def touched_paddrs_def
   apply force
  done

lemma page_table_inv_preserved':
  "\<lbrakk>a # p \<in> programs_obeying_ta (other_state s); a # p \<in> programs_safe (other_state s);
    touched_addrs_inv' s; page_table_inv' s; (s, t) \<in> uwr (current_domain' s);
    s' = instr_multistep p (instr_step a s); t' = instr_multistep p (instr_step a t);
    d = current_domain' s; current_domain' (instr_step a s) = d\<rbrakk>
   \<Longrightarrow> page_table_inv' (instr_step a s)"
  apply(clarsimp simp:programs_obeying_ta_def programs_safe_def)
  using page_table_inv_preserved by blast
*)


(* d running \<rightarrow> d running *)
lemma d_running: "\<lbrakk>
   \<comment> \<open>Note: The \<open>programs_obeying_ta_preserve_uwr\<close> lemma that uses this should extract whatever
     we'll need here from its guards that s and t are reachable. We can't have these reachability
     guards here because it will mess up the induction proof (won't hold for intermediate states).\<close>
   \<comment> \<open>we have two programs derived from the same touched_addresses -
     these have to be the same program (so we need to know that the choice depends on stuff in
     other_state in the external uwr)\<close>
   p \<in> programs_obeying_ta os';
   \<comment> \<open>that touched_addresses ONLY contains addresses in d\<close>
   touched_addrs_inv os';
   \<comment> \<open>initial states s and t hold uwr_running\<close>
   ((os, s), (ot, t)) \<in> uwr d;
   (os', ot') \<in> external_uwr d;
   current_domain os = d;
   \<comment> \<open>NB: external_uwr should give us current_domain' t = d\<close>
   \<comment> \<open>we execute the program on both states\<close>
   s' = instr_multistep p os s;
   t' = instr_multistep p ot t;
   current_domain os' = current_domain os;
   current_domain ot' = current_domain ot
   \<rbrakk> \<Longrightarrow>
   \<comment> \<open>new states s' and t' hold uwr_running\<close>
   ((os', s'), (ot', t')) \<in> uwr d"
  sorry
   (*
  apply(induct p arbitrary:s t os ot)
   apply (solves \<open>clarsimp simp:uwr_def\<close>)
  apply clarsimp
  apply(erule_tac x="instr_step a s" in meta_allE)
  apply(erule_tac x="instr_step a t" in meta_allE)
  apply clarsimp
  apply(erule meta_impE)
   apply(clarsimp simp:programs_obeying_ta_def instrs_obeying_ta_def list_all_def split:instr.splits)
     apply(force simp add:touched_paddrs_def paddrs_of_def page_table_not_in_mem touched_addrs_not_in_mem)
    unfolding touched_paddrs_def paddrs_of_def
  apply(erule meta_impE)
   apply(clarsimp simp: programs_safe_def instrs_safe_def list_all_def split:instr.splits)
    (* Isar proof found by sledgehammer -robs. *)
    using page_table_not_in_mem apply auto[1]
  apply (subgoal_tac "current_domain' (instr_step a s) = d")
   apply (erule meta_impE)
    apply(clarsimp simp:programs_obeying_ta_def programs_safe_def)
    using touched_addrs_inv_preserved
    apply blast
   apply (erule meta_impE)
    apply(clarsimp simp:programs_obeying_ta_def programs_safe_def)
    using page_table_inv_preserved
    apply blast
   apply(metis (no_types, lifting) d_running_step hd_instr_obeying_ta list_all_simps(1) mem_Collect_eq time_protection.programs_safe_def time_protection_axioms)
  using safe_no_domainswitch
  apply (metis list_all_simps(1) mem_Collect_eq programs_safe_def)
  done *)

definition is_domainswitch_gadget where
  "is_domainswitch_gadget p \<equiv> True"

lemma d_not_running_step:
  assumes
  "i \<in> instrs_obeying_ta os"
  "touched_addrs_inv os"
  "current_domain os \<noteq> d"
  "s' = instr_step i os s"
  "currentdomain os' = curren_domain os"
  shows
  "((os, s), (os', s')) \<in> uwr d"
  oops (*
  proof (cases i)
    case (IRead x1)
    then show ?thesis using assms
      apply (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def
                            instrs_obeying_ta_def)
      (* show that the instruction hasn't affected our visible part of pch *)
      apply (drule in_inter_empty)
       apply force
      apply (clarsimp simp: all_paddrs_of_def)
      apply (rule pch_partitioned_read, clarsimp)
      using diff_domain_no_collision
      by (metis (mono_tags, lifting) Un_iff all_paddrs_of_def collision_sym
        kernel_shared_expanded_def mem_Collect_eq page_table_inv_def)
  next
    case (IWrite x2)
    then show ?thesis using assms
      apply (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def
                            instrs_obeying_ta_def)
      apply (thin_tac "s' = _")
      apply (drule in_inter_empty)
       apply force
      apply (intro conjI)
       apply (clarsimp simp: all_paddrs_of_def)
       apply (rule pch_partitioned_write, clarsimp)
       using diff_domain_no_collision
       apply (metis (mono_tags, lifting) Un_iff all_paddrs_of_def collision_sym
         kernel_shared_expanded_def mem_Collect_eq page_table_inv_def)
      apply (rule do_write_maintains_external_uwr_out)
      apply (clarsimp simp: all_paddrs_of_def)
      apply (clarsimp simp: instrs_safe_def kernel_shared_precise_def)
      by (metis (mono_tags) Un_iff all_paddrs_of_def kernel_shared_precise_def mem_Collect_eq
        page_table_inv_def)
  next
    case (IRegs x3)
    then show ?thesis using assms
      by (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def)
  next
    case IFlushL1
    then show ?thesis using assms
      by (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def)
  next
    case (IFlushL2 x5)
    then show ?thesis using assms
      apply (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def
                            instrs_obeying_ta_def)
      apply (rule sym, rule pch_partitioned_flush, clarsimp)
      apply(clarsimp simp:touched_addrs_inv_def all_paddrs_of_def)
      (* Adapted from Isar proof found by Sledgehammer -robs. *)
      apply(prop_tac "addr_domain a' = d")
       using diff_domain_no_collision
       apply blast
      apply(prop_tac "a \<in> kernel_shared_precise")
       apply(force simp:kernel_shared_precise_def)
      using collision_set_contains_itself kernel_shared_expanded_def
      apply blast
      done
  next
    case IReadTime
    then show ?thesis using assms
      by (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def)
  next
    case (IPadToTime x7)
    then show ?thesis using assms
      by (clarsimp simp: uwr_def uwr_notrunning_def pch_same_for_domain_except_shared_def)
qed *)


lemma programs_obeying_ta_head_and_rest:
  "h # r \<in> programs_obeying_ta ta \<Longrightarrow>
   h \<in> instrs_obeying_ta ta \<and> r \<in> programs_obeying_ta ta"
  apply (clarsimp simp: programs_obeying_ta_def)
  done

lemma d_not_running_integrity_uwr:
  "\<lbrakk>p \<in> programs_obeying_ta os;
  current_domain os \<noteq> d;
  touched_addrs_inv os
  \<rbrakk> \<Longrightarrow>
  ((os, s), (os, instr_multistep p os s)) \<in> uwr d"
  oops (*
  apply (induct p arbitrary: s; clarsimp)
  apply (drule programs_obeying_ta_head_and_rest, clarsimp)
  apply (drule programs_safe_head_and_rest, clarsimp)
  apply (subgoal_tac "current_domain' (instr_step a s) \<noteq> d")
   defer
   using safe_no_domainswitch
   apply blast
  unfolding programs_obeying_ta_def programs_safe_def
  apply (drule_tac x="instr_step a s" in meta_spec)
  apply(erule meta_impE)
   apply(clarsimp simp:instrs_obeying_ta_def instrs_safe_def list_all_def split:instr.splits)
    using page_table_not_in_mem touched_paddrs_def
    apply(force simp add: touched_addrs_not_in_mem paddrs_of_def)
  apply(erule meta_impE)
   apply(clarsimp simp:instrs_obeying_ta_def instrs_safe_def list_all_def split:instr.splits)
    using page_table_not_in_mem touched_paddrs_def paddrs_of_def touched_addrs_not_in_mem
    apply (force simp add: do_write_outside_kernelshared_same_domain kernel_shared_precise_def)
  apply(erule meta_impE)
   apply force
  apply(erule meta_impE)
   using touched_addrs_inv_preserved
   apply(force simp add: safe_no_domainswitch)
  apply(erule meta_impE)
   using page_table_inv_preserved
   apply(force simp add: safe_no_domainswitch)
  apply (rule_tac b="instr_step a s" in uwr_trans)
   defer
   apply assumption
  (* now we are down to the single step *)
  defer
  apply (erule_tac i=a in d_not_running_step; simp)
  done *)

(* d not running \<rightarrow> d not running *)
lemma d_not_running: "\<lbrakk>
   \<comment> \<open>we have two programs derived from touched_addresses - may not be the same touched_addresses\<close>
   ps \<in> programs_obeying_ta os';
   pt \<in> programs_obeying_ta ot';
   \<comment> \<open>we may not have concrete touched_addresses -
     we may overapprox this to the whole currently running domain.
     NB: I think it's enough just to require it not contain any of d's addresses. -robs.\<close>
   \<comment> \<open>these touched_addresses does NOT contain any addresses from d\<close>
   touched_addrs_inv os';
   touched_addrs_inv ot';
   \<comment> \<open>initial states s and t hold uwr_notrunning\<close>
   ((os, s), (ot, t)) \<in> uwr d;
   current_domain os \<noteq> d;
   \<comment> \<open>NB: external_uwr should give us current_domain' t \<noteq> d\<close>
   \<comment> \<open>we execute both programs\<close>
   s' = instr_multistep ps os s;
   t' = instr_multistep pt ot t;
   current_domain' s' \<noteq> d;
   current_domain os' = current_domain os;
   current_domain ot' = current_domain ot
   \<comment> \<open>NB: external_uwr should oblige us to prove current_domain' t' \<noteq> d\<close>
   \<rbrakk> \<Longrightarrow>
   \<comment> \<open>new state s' and t' hold uwr_notrunning\<close>
   ((os', s'), (ot', t')) \<in> uwr d"
  sorry (*
  apply clarsimp
  apply (subgoal_tac "current_domain' t \<noteq> d")
   apply (drule(4) d_not_running_integrity_uwr [where s=s])
   apply (drule(4) d_not_running_integrity_uwr [where s=t])
  apply (rule uwr_trans, subst uwr_sym, assumption)
   apply (rule uwr_trans, assumption, assumption)
  using uwr_same_domain apply blast
  done *)
  
  

(* --- notes for domainswitch step stuff ---- *)


lemma dirty_step_u_1of3:
  assumes
    "i \<in> instrs_obeying_set os (all_paddrs_of u)"
    "((os, s), (ot, t)) \<in> uwr u"
    "(os', ot') \<in> external_uwr u"
    "s' = instr_step i os s"
    "t' = instr_step i ot t"
    "current_domain os = u"
  shows
    "((os, s'), (os, t')) \<in> uwr u"
  proof (cases i)
case (IRead x1)
  then show ?thesis using assms
   apply (clarsimp simp: instrs_obeying_set_def)
   apply (clarsimp simp: uwr_def uwr_running_def)
   apply (intro conjI)
    apply (clarsimp simp: pch_same_for_domain_and_shared_def)
    apply (prop_tac "v_to_p ot x1 = v_to_p os x1")
      subgoal sorry
    apply (intro conjI; clarsimp)
     apply (metis (mono_tags, lifting) collision_sym diff_domain_no_collision pch_collision_read pch_partitioned_read)
    apply (metis (no_types, lifting) external_uwr_current_page_table full_collision_set_def kernel_shared_expanded_full_collision_set pch_collision_read pch_partitioned_read)
   apply (simp add: all_paddrs_of_def external_uwr_current_page_table pch_same_for_domain_and_shared_def)
  done
  oops

(* one step of a dirty program holding uwr apart from time *)
lemma dirty_step_u:
  assumes
    (* "i \<in> instrs_obeying_set os (all_paddrs_of u \<union> all_paddrs_of v \<union> kernel_shared_precise)" *)
    "((os, s), (ot, t)) \<in> uwr u"
    (* "(os', ot') \<in> external_uwr u" *)
    "s' = instr_step i os s"
    "t' = instr_step i ot t"
    "current_domain os = u"
  shows
    "((os, s'), (os, t'\<lparr>tm:=tm s'\<rparr>)) \<in> uwr u"
  proof (cases i)
  case (IRead a)
  then show ?thesis using assms
   apply (clarsimp simp: uwr_def uwr_running_def)
   apply (thin_tac "s' = _", thin_tac "t' = _")
   apply (prop_tac "v_to_p ot = v_to_p os")
    using external_uwr_current_page_table apply blast
  apply (clarsimp simp: pch_same_for_domain_and_shared_def)
  apply (intro conjI; clarsimp)
   apply (metis (no_types, lifting) collision_sym diff_domain_no_collision pch_collision_read pch_partitioned_read)
  apply (metis (no_types, lifting) full_collision_set_def kernel_shared_expanded_full_collision_set pch_collision_read pch_partitioned_read)
  done
next
  case (IWrite a)
  then show ?thesis using assms
   apply (clarsimp simp: uwr_def uwr_running_def)
   apply (thin_tac "s' = _", thin_tac "t' = _")
   apply (prop_tac "v_to_p ot = v_to_p os")
    using external_uwr_current_page_table apply blast
  apply (clarsimp simp: pch_same_for_domain_and_shared_def)
  apply (intro conjI; clarsimp)
   apply (rule pch_collision_write)
      defer
      
next
  case IFlushL1
  then show ?thesis sorry
next
  case (IFlushL2 x4)
  then show ?thesis sorry
next
  case (IPadToTime x5)
  then show ?thesis sorry
qed

lemma dirty_step:
  assumes
  "i \<in> instrs_obeying_set os (all_paddrs_of u \<union> all_paddrs_of v \<union> kernel_shared_precise)"
  "s' = instr_step i os s"
  shows
  "((os, s), (os, s')) \<in> uwr d"
  proof (cases i)
case (IRead x1)
  then show ?thesis using assms
   apply (clarsimp simp: instrs_obeying_set_def)
   next
     case (IWrite x2)
     then show ?thesis sorry
   next
     case IFlushL1
     then show ?thesis sorry
   next
     case (IFlushL2 x4)
     then show ?thesis sorry
   next
     case (IPadToTime x5)
  then show ?thesis sorry
qed

lemma dirty_domainswitch_semi_uwr: "\<lbrakk>
  correct_dirty_programs dpg;
  same_dirty_programs dpg;
  ((os, s), (ot, t)) \<in> uwr d;
  (os', ot') \<in> external_uwr d;
  ps = dpg u v os;
  pt = dpg u v ot;
  s' = instr_multistep ps os s;
  t' = instr_multistep pt ot t;
  True
  \<rbrakk> \<Longrightarrow>
  ((os', s'), (ot', t')) \<in> uwr d"
  apply (prop_tac "pt = ps")
   apply (metis external_uwr_Sched same_dirty_programs_def uwr_external_uwr)
  apply clarsimp
  apply (clarsimp simp:correct_dirty_programs_def)
  

lemma domainswitch_uwr: "\<lbrakk>
  correct_dirty_programs dpg;
  same_dirty_programs dpg;
  same_next_time ntg;
  ps = get_domain_switch_program dpg ntg u v os;
  pt = get_domain_switch_program dpg ntg u v ot;
  ((os, s), (ot, t)) \<in> uwr d;
  (os', ot') \<in> external_uwr d;
  s' = instr_multistep ps os s;
  t' = instr_multistep pt ot t;
  True
  \<rbrakk> \<Longrightarrow>
  ((os', s'), (ot', t')) \<in> uwr d"
  nitpick










(*

  
  - firstly, a ta-based step
  - then, SPECIFIC OPERATIONS



  A domainswitch step from u1 to u2 will look like:
  - some operations that obey TA as with other steps (and therefore
    also preserve the appropriate UWR.
  - now a very speifically defined set of operations, at the instruction level:
    - change the domain (this changes other_state memory)
    - flush pch for kernel shared precise
    - flush fch
    - pad to time
    - load registers
      - this is a series of reads from u2's memory, and it results in a total "regs" state
        that is dependent only upon u2's memory.

  We conceptualise a domainswitch in those two stages. first, something underdefined
  that follows normal TA rules, so the existing proofs will work happily with those.
  Then, we have a strictly defined program that is 


  Why this works:
  For the to-running case:
  - start with u2 running. uwr u1 gives:
    - same pch for that domain except kernel_shared_extended
    - same external uwr (means external memory for u1)
  - we end with u1 running. uwr u1 now requires:
    - same pch for that domain PLUS kernel_shared_expanded
      - we can get this from the pch flush, and the exit-path only reading from u1 AND
        being a totally defined set of instructions will create a uniform impact on all
        of the pch that we care about.
    - same fch totally
      - this becomes the same on fch flush, then padding and exitpath/regload must
        have a uniform impact on it.
    - same time
      - at the start we have no idea about time, so we need some way of knowing that
        pad-to-time will both pad to exactly the same time. after that, the exit path is
        deterministic isntructions that depend only on state on u1, so will be consistent.
    - same regs
      - we need to konw that the exit path overrides all regs, from u1's memory,
        so they will be the same at the end.
    - same other_state
      - this will be given by an external property.

  For the from-running case:
  - start with u1 running. uwr u1 gives:
    - same pch for that domain PLUS kernel shared
    - same fch
    - same time
    - same regs
    - other_state from external_uwr
  - we end with u2 running. uwr u1 requires:
    - same pch for that domain EXCEPT kernel shared
      - none of the operations will affect u1's part of pch
    - same other_state
      - this will be given by an external property


*)

(*

(* this will mostly mimic the requirements for non-domainswitch step requirements *)
(*FIXME: define this *)
definition
  is_simple_program_d :: "'userdomain domain \<Rightarrow> 'regs program \<Rightarrow> bool" where
  "is_simple_program_d d p \<equiv> True"

(* this is an instruction that sets the domain to d. *)
(*FIXME: perhaps "\<forall>s" is too strong? Perhaps not.*)
definition
  is_domainswitch_instr :: "'userdomain domain \<Rightarrow> 'regs instr \<Rightarrow> bool" where
  "is_domainswitch_instr d i \<equiv> \<forall> s. current_domain' (instr_step i s) = d"

(* this is the time that will end current domain slice *)
(*FIXME: implement properly
  notes: schedule_oracle might be the way to implement this. however,
    there needs to be some point at which the concept of time in this model
    is connected to the looser concepts of time in seL4 spec. Not sure if this
    is one of the places for that connection to occur though.

 *)
definition
  fully_padded_time :: "time \<Rightarrow> time" where
  "fully_padded_time t \<equiv> 12345"

(* this is a (very specific) program that reads registers from memory.
   requirements:
   - leaves regs in a state that is dependent ONLY on domain `d` (ie removes all previous regs state)
   - needs to have an impact on fch and pch that is dependent only on stuff visible to d2
   - needs to take a bounded amount of time

   implementation ideas:
   - i think this is only a series of reads.
   - probably a set number of reads.
   - the list of addresses is probably set too - determined by the domain.
   - the read addresses are domain-confined.
   - how do we bound the time? a set number of reads, and a read has a max time?
   - regs impact of read isn't strongly defined in this model. we just assert here that
     regs will be overwritten completely. knowing that regs state might require a state input.
*)
definition
  is_loadregs_program :: "'userdomain domain \<Rightarrow> 'regs program \<Rightarrow> bool" where
  "is_loadregs_program d p \<equiv> True"

(* the given program is a domainswitch program. This means a program that starts in domain d1,
  at time t, switches to domain d2, and performs all the appropriate steps along the way. *)
definition
  is_domainswitch_program :: "'userdomain domain \<Rightarrow> 'userdomain domain \<Rightarrow> time \<Rightarrow> 'regs program \<Rightarrow> bool" where
  "is_domainswitch_program d1 d2 t p \<equiv> \<exists> p1 iswitch pregs.
                                       p = p1
                                         @ [iswitch,
                                            IFlushL2 kernel_shared_precise,
                                            IFlushL1,
                                            IPadToTime (fully_padded_time t)]
                                         @ pregs
                                     \<and> is_simple_program_d d1 p1
                                     \<and> is_domainswitch_instr d2 iswitch
                                     \<and> is_loadregs_program d2 pregs"

*)

(* question:

  - time in this model and in seL4. does there need to be some relationship between time in this
    model and time in the seL4 model? at what point is this link made? This probably needs to be
    part of the integration, but then our use of a scheduler oracle needs to line up with that
    somehow.
*)



(* XXX: Just commenting it out unchanged to avoid any nasty merge conflicts -robs.
(*FIXME: This is a draft *)
(* d running \<rightarrow> d not running *)
lemma context_switch_from_d: "\<lbrakk>
   p \<in> programs_obeying_ta ta;
   ta \<inter> all_paddrs_of d = {};
   (s, t) \<in> uwr d;
   current_domain' s = d;
   \<comment> \<open>NB: external_uwr should give us current_domain' t = d\<close>
   s' = instr_multistep p s;
   t' = instr_multistep p t;
   current_domain' s' \<noteq> d
   \<comment> \<open>NB: external_uwr should oblige us to prove current_domain' t' \<noteq> d\<close>
   \<rbrakk> \<Longrightarrow>
   (s', t') \<in> uwr d"
  oops

(* d not running \<rightarrow> d running *)
lemma context_switch_to_d: "\<lbrakk>
   p\<^sub>s \<in> programs_obeying_ta ta\<^sub>s;
   p\<^sub>t \<in> programs_obeying_ta ta\<^sub>t;
   ta\<^sub>s \<inter> all_paddrs_of d \<subseteq> kernel_shared_precise;
   ta\<^sub>t \<inter> all_paddrs_of d \<subseteq> kernel_shared_precise;
   (s, t) \<in> uwr d;
   current_domain' s \<noteq> d;
   \<comment> \<open>external_uwr should give us current_domain' t \<noteq> d\<close>do_read
   s' = instr_multistep (p\<^sub>s @ [IFlushL1, IPadToTime detTime]) s;
   t' = instr_multistep (p\<^sub>t @ [IFlushL1, IPadToTime detTime]) t;
   current_domain' s' = d
   \<comment> \<open>external_uwr should oblige us to prove current_domain' t' = d\<close>
   \<rbrakk> \<Longrightarrow>
   (s', t') \<in> uwr d"
  oops
*)




(* not sure if we need this any more.
   if it's just combining running and not_running, it could be useful.
   will leave it here for now. -scott

lemma programs_obeying_ta_preserve_uwr: "\<lbrakk>
   \<not> will_domain_switch (other_state s);
   \<not> will_domain_switch (other_state t);
   touched_addrs_inv' s;
   touched_addrs_inv' t;
   page_table_inv' s;
   page_table_inv' t;
   is_secure_nondomainswitch p\<^sub>s s;
   is_secure_nondomainswitch p\<^sub>t t;
   (s, t) \<in> uwr d;
   current_domain' s = d \<longrightarrow> p\<^sub>s = p\<^sub>t;
   s' = instr_multistep p\<^sub>s s;
   t' = instr_multistep p\<^sub>t t
   \<rbrakk> \<Longrightarrow>
   (s', t') \<in> uwr d"
  apply(clarsimp simp:is_secure_nondomainswitch_def)
  apply(frule uwr_same_domain)
  apply(case_tac "current_domain' s = d")
   apply clarsimp
   apply(prop_tac "current_domain' s' = d")
    apply(metis no_domainswitch_inv)
   apply(force intro:d_running)
  apply(prop_tac "current_domain' s' \<noteq> d")
   apply(metis no_domainswitch_inv)
  apply clarsimp
  apply(force intro:d_not_running[where s=s and t=t and p\<^sub>s=p\<^sub>s and p\<^sub>t=p\<^sub>t])
  done
 *)
end


(* give me:
   - a domain extractor
   - an unwinding relation
   - a state
   - a set of programs
   and i'll give you a program. i only use information inside the uwr to decide which program
   to choose, and i will always choose from the given set of programs. *)
axiomatization
  SelectProgram :: "('s \<Rightarrow> 'd) \<Rightarrow>('d \<Rightarrow> ('s \<times> 's) set) \<Rightarrow> ('s \<Rightarrow> 'p set) \<Rightarrow> 's \<Rightarrow> 'p"
where
  program_uwr_determined : "(s, t) \<in> uwr (cdom s) \<Longrightarrow>
                            SelectProgram cdom uwr get_ps s = SelectProgram cdom uwr get_ps t"
and
  program_from_set : "get_ps s \<noteq> {} \<Longrightarrow> SelectProgram cdom uwr get_ps s \<in> get_ps s"


locale time_protection_system =
  ab: unwinding_system A s0 "\<lambda>_. current_domain" external_uwr policy out Sched +
  tp?: time_protection collides_in_pch fch_lookup pch_lookup
    fch_read_impact pch_read_impact fch_write_impact pch_write_impact
    read_cycles write_cycles empty_fch fch_flush_cycles do_pch_flush pch_flush_cycles
    addr_domain addr_colour colour_userdomain current_domain external_uwr v_to_p
    touched_addrs will_domain_switch
  for A :: "('a,'other_state,unit) data_type"
  and s0 :: "'other_state"
  and current_domain :: "'other_state \<Rightarrow> 'userdomain domain"
  and external_uwr :: "'userdomain domain \<Rightarrow> ('other_state \<times> 'other_state) set"
  and policy :: "('userdomain domain \<times> 'userdomain domain) set"
  and out :: "'userdomain domain \<Rightarrow> 'other_state \<Rightarrow> 'p"
  and collides_in_pch :: "paddr \<Rightarrow> paddr \<Rightarrow> bool"
  and fch_lookup :: "'fch \<Rightarrow> 'fch_cachedness fch"
  and pch_lookup :: "'pch \<Rightarrow> 'pch_cachedness pch"
  and fch_read_impact :: "'fch fch_impact"
  and pch_read_impact :: "'pch pch_impact"
  and fch_write_impact :: "'fch fch_impact"
  and pch_write_impact :: "'pch pch_impact"
  and read_cycles  :: "'fch_cachedness \<Rightarrow> 'pch_cachedness \<Rightarrow> time"
  and write_cycles :: "'fch_cachedness \<Rightarrow> 'pch_cachedness \<Rightarrow> time"
  and empty_fch :: "'fch"
  and fch_flush_cycles :: "'fch \<Rightarrow> time"
  and do_pch_flush :: "'pch \<Rightarrow> paddr set \<Rightarrow> 'pch"
  and pch_flush_cycles :: "'pch \<Rightarrow> paddr set \<Rightarrow> time"
  and addr_domain :: "paddr \<Rightarrow> 'userdomain domain"
  and addr_colour :: "paddr \<Rightarrow> 'colour"
  and colour_userdomain :: "'colour \<Rightarrow> 'userdomain"
  and v_to_p :: "'other_state \<Rightarrow> vaddr \<Rightarrow> paddr"
  and touched_addrs :: "'other_state \<Rightarrow> vaddr set"
  and will_domain_switch :: "'other_state \<Rightarrow> bool" +
  fixes initial_pch :: "'pch"
  fixes choose_next_domain :: "'userdomain domain \<Rightarrow> 'userdomain domain"
  assumes reachable_touched_addrs_inv:
    "ab.reachable s \<Longrightarrow> touched_addrs_inv s"
  assumes simple_steps:
    "(s, s') \<in> ab.Step () \<Longrightarrow>
    (\<not>will_domain_switch s \<and> current_domain s' = current_domain s)
    \<or> (will_domain_switch s \<and> current_domain s' = choose_next_domain (current_domain s))"
begin

(* this is an axiomatised selector that gets one program from a set.
  it is not defined which program will be selected. *)
abbreviation selectProgram :: "'other_state \<Rightarrow> program"
  where
  "selectProgram \<equiv> SelectProgram current_domain external_uwr programs_obeying_ta"

(* this used to be called A_extened_Step *)
definition maStep :: "unit \<Rightarrow>
  (('other_state\<times>('fch, 'pch)state) \<times> ('other_state\<times>('fch, 'pch)state)) set"
  where
  "maStep _ \<equiv> {((os, s), (os', s')) | os os' s s' p.
              (os, os') \<in> ab.Step () \<and>
               ((\<not>will_domain_switch os
                 \<and> p = selectProgram os'
                 \<and> s' = instr_multistep p os s ) \<comment> \<open>TA step\<close>
               \<or> (will_domain_switch os
                 \<and> is_domainswitch_gadget p
                 \<and> s' = instr_multistep p os s ) \<comment> \<open>gadget step\<close>
              )}"

definition maA :: "(('other_state\<times>('fch, 'pch)state), ('other_state\<times>('fch, 'pch)state), unit) data_type" where
  "maA \<equiv> \<lparr> Init = \<lambda>s. {s}, Fin = id, Step = maStep\<rparr>"

(* instead of A_extended_state *)
definition mas0 :: "'other_state\<times>('fch, 'pch)state" where
  "mas0 \<equiv> (s0, \<lparr>fch=empty_fch, pch=initial_pch, tm=0\<rparr>)"

interpretation ma?:Init_inv_Fin_system maA mas0
  apply unfold_locales
    (* Init_Fin_system.Fin_Init_s0 *)
    apply(force simp:maA_def mas0_def)
   (* Init_Fin_system.Init_inv_Fin *)
   apply(force simp:maA_def)
  (* Init_Fin_system.Fin_inj *)
  apply(force simp:maA_def)
  done

lemma ma_to_ab_step:
  "((os, s), (os', s')) \<in> ma.Step () \<Longrightarrow>
   (os, os') \<in> ab.Step ()"
  apply (clarsimp simp: ma.Step_def execution_def maA_def system.Step_def steps_def maStep_def)
  done

lemma ma_to_ab_run:
  "((os, s), (os', s')) \<in> Run ma.Step as \<Longrightarrow>
   (os, os') \<in> Run ab.Step as"
  apply(induct as arbitrary:s os, solves \<open>simp\<close>)
  apply clarsimp
  apply(erule_tac x=ba in meta_allE)
  apply(erule_tac x=aa in meta_allE)
  apply (drule ma_to_ab_step)
  apply clarsimp
  by blast

lemma ma_to_ab_reachable:
  "ma.reachable (os, s) \<Longrightarrow> ab.reachable os"
  apply(rule ab.Run_reachable)
  apply(drule ma.reachable_Run, clarsimp)
  apply(rule_tac x=as in exI)
  apply (clarsimp simp:mas0_def)
  using ma_to_ab_run apply blast
  done

lemma ma_to_ab_reachable':
  "ma.reachable s \<Longrightarrow> ab.reachable (fst s)"
  apply (cases s, clarsimp simp:ma_to_ab_reachable)
  done

lemma ma_single_step_enabled:
  "ab.reachable os \<Longrightarrow>
   \<exists>s' os'. ((os, s), os', s') \<in> {(s, s'). s' \<in> steps maStep {s} [()]} \<and> ab.reachable os'"
  apply (clarsimp simp: steps_def maStep_def)
  apply (cases "will_domain_switch os"; clarsimp)
  using ab.enabled_Step is_domainswitch_gadget_def ab.reachable_Step apply fastforce
  using ab.enabled_Step ab.reachable_Step apply blast
done

lemma ma_execution_enabledness:
  "ab.reachable os \<Longrightarrow>
   ma.reachable (os, s) \<Longrightarrow>
   \<exists>s' os'. (os', s') \<in> execution maA (os, s) js"
  apply (subst ma.execution_Run [OF _], simp)
  apply (thin_tac "ma.reachable _")
  apply (induct js arbitrary:os s)
   apply (clarsimp simp: execution_def steps_def maA_def)
  apply clarsimp
  apply (clarsimp simp:ma.Step_def execution_def maA_def maStep_def system.Step_def)
  apply (simp only:maA_def [symmetric])
  using ma_single_step_enabled apply (meson relcomp.relcompI)
  done

(* note: we're given an 'out' in time_protection_system, and here we just adjust it to look at
   the other_state part of the new ma state *)
interpretation ma: unwinding_system maA mas0 "\<lambda>_ s. current_domain (fst s)" uwr policy "\<lambda>d s. out d (fst s)" Sched
  apply unfold_locales
      (* enabled_system.enabled *)
      apply(simp only:system.reachable_def[symmetric])
      apply (frule ma_to_ab_reachable')
      apply (simp only:ab.reachable_def)
      apply (frule_tac js=js in ab.enabled)
      apply (frule ma_to_ab_reachable')
      using ma_execution_enabledness apply fastforce 
     (* noninterference_policy.uwr_equiv_rel *)
     using uwr_equiv_rel apply blast
    (* noninterference_policy.schedIncludesCurrentDom *)
    using external_uwr_same_domain uwr_external_uwr apply fastforce
   (* noninterference_policy.schedFlowsToAll *)
   using ab.schedFlowsToAll apply blast
  (* noninterference_policy.schedNotGlobalChannel *)
  using ab.schedNotGlobalChannel apply blast
  done

lemma ma_confidentiality_u_ta:
  "\<lbrakk>\<not>will_domain_switch os;
  touched_addrs_inv os';
  touched_addrs_inv ot';
  ma.uwr2 (os, s) u (ot, t);
  ab.uwr2 os' u ot';
  ((os, s), os', s') \<in> maStep ();
  ((ot, t), ot', t') \<in> maStep ()\<rbrakk>
  \<Longrightarrow> ma.uwr2 (os', s') u (ot', t')"
  apply (frule uwr_external_uwr)
  apply (frule will_domain_switch_public [where os=os])
  apply (clarsimp simp:maStep_def)

  (* show that the domain hasn't changed *)
  apply (frule simple_steps [where s=os]; clarsimp)
  apply (frule simple_steps [where s=ot]; clarsimp)

  (* show that the programs obey the TAs *)
  apply (prop_tac "selectProgram os' \<in> programs_obeying_ta os'
                 \<and> selectProgram ot' \<in> programs_obeying_ta ot'")
    apply (intro conjI; rule program_from_set)
    (* I guess this should be a locale assumption? *)
    subgoal sorry
    subgoal sorry
  apply clarsimp

  apply (case_tac "current_domain os = u")
   (* u is executing *)
   apply (prop_tac "selectProgram ot' = selectProgram os'")
    apply (subst eq_sym_conv)
    apply (rule program_uwr_determined, simp)
   apply (erule(2) d_running, simp+)
  (* u is not executing *)
  apply (rule d_not_running [where os=os and ot=ot], simp+)
  done

theorem ma_confidentiality_u:
  "ab.confidentiality_u \<Longrightarrow> ma.confidentiality_u"
  apply(clarsimp simp:ma.confidentiality_u_def)
  apply (rename_tac u os s ot t os' s' ot' t')

  apply (prop_tac "ab.uwr2 os' u ot'")
   apply (simp only:ab.confidentiality_u_def)
   apply (meson ma_to_ab_reachable ma_to_ab_step uwr_external_uwr)
  
  apply (drule(1) ma.reachable_Step)+

  apply (frule_tac os=os' in ma_to_ab_reachable)
  apply (frule_tac os=ot' in ma_to_ab_reachable)
  apply (drule reachable_touched_addrs_inv)+
  
  apply (thin_tac "_ \<longrightarrow> _")
  apply (thin_tac "ma.uwr2 _ Sched _")

  (* let's get this all in terms of maStep *)
  apply (clarsimp simp:ma.Step_def execution_def steps_def maA_def system.Step_def)
  apply (simp only:maA_def [symmetric])

  apply (case_tac "will_domain_switch os")
   defer
   apply (erule ma_confidentiality_u_ta; simp)

  

  apply(frule will_domain_switch_public)
  apply(case_tac "will_domain_switch (other_state s)")
   apply(clarsimp simp:Let_def)
   apply(frule_tac s'="instr_multistep (C_step_program (other_state s) (Fin C x)) s"
         in reachable_C_domainswitch_secure)
     apply(clarsimp simp:conc.Step_def execution_def steps_def)
     apply blast
    apply force
   apply(clarsimp simp:is_secure_domainswitch_def)
   apply(erule_tac x=u in allE)
   apply(erule_tac x=t in allE)
   apply clarsimp
   apply(rename_tac u s t s_priv' s_priv t_priv' t_priv)
   apply(erule_tac x="instr_multistep (C_step_program (other_state t) (Fin C t_priv')) t" in allE)
   apply(clarsimp simp:conc.Step_def execution_def steps_def)
   apply blast
  apply(clarsimp simp:Let_def)
  apply(rename_tac u s t s_priv' s_priv t_priv' t_priv)
  apply(rule programs_obeying_ta_preserve_uwr, simp_all)
      apply(force simp:A_touched_addrs_inv reachable)
     apply(force simp:A_touched_addrs_inv reachable)
    apply(force simp:A_page_table_inv reachable)
   apply(force simp:A_page_table_inv reachable)
  apply(force simp:kludge_uwr_same_programs_def)
  done

theorem extended_Nonleakage:
  "abs.Nonleakage_gen \<Longrightarrow> tpni.Nonleakage_gen"
  apply(prop_tac "conc.Nonleakage_gen")
   apply(force intro:Nonleakage_gen_refinement_closed)
  using conc.Nonleakage_gen_confidentiality_u extended_confidentiality_u tpni.Nonleakage_gen
  by blast

end
end