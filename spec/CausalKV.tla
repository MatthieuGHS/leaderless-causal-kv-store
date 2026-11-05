---------------------------- MODULE CausalKV ----------------------------
(***************************************************************************)
(* KV store répliqué sans leader, diffusion CO-URB, siblings.              *)
(* Niveau d'abstraction : URB est supposé (pas de relais modélisé).        *)
(* L'ensemble `sent` contient tous les messages diffusés ; chaque réplique *)
(* vivante peut délivrer n'importe lequel, si la condition DC le permet.   *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Proc,        \* les répliques, ex. {1, 2, 3}
          Key, Val,    \* clés et valeurs possibles
          MaxPut,      \* nombre max de put (borne le modèle pour TLC)
          MaxCrash,    \* nombre max de crashs (t)
          Mode         \* "co" (CO-URB) ou "naive" (best-effort, le témoin)

VARIABLES sent,        \* ensemble des messages diffusés
          lost,        \* paires <<j, m>> : m ne parviendra jamais à j (naïf seulement)
          dlv,         \* dlv[i] : séquence des messages délivrés par i (= log)
          cp,          \* cp[i]  : vecteur causalPast de i
          store,       \* store[i][k] : ensemble de couples <<valeur, vecteur>>
          crashed,     \* ensemble des répliques crashées
          nput         \* nombre de put déjà faits

vars == <<sent, lost, dlv, cp, store, crashed, nput>>

----------------------------------------------------------------------------
(* Vecteurs : équivalent du module Store                                   *)

Zero      == [k \in Proc |-> 0]
Leq(a, b) == \A k \in Proc : a[k] <= b[k]                 \* leq?
Lt(a, b)  == Leq(a, b) /\ a # b                           \* lt?

\* étiquette de la version écrite par m : m.cp avec +1 sur la case de l'émetteur
V(m) == [k \in Proc |-> IF k = m.sender THEN m.cp[k] + 1 ELSE m.cp[k]]   \* version

\* règle d'écriture du KV : garder les versions non dominées, ajouter la nouvelle
ApplyWrite(vs, w) == {x \in vs : ~Lt(x[2], w[2])} \cup {w}               \* apply_write

Delivered(i) == {dlv[i][x] : x \in 1..Len(dlv[i])}

\* condition de délivrance de CO : tout le passé causal de m est déjà délivré
DC(i, m) == Leq(m.cp, cp[i])

\* effet commun à toute délivrance de m sur i (= deliver dans replica.ex)
DoDeliver(i, m) ==
  /\ dlv'   = [dlv   EXCEPT ![i] = Append(@, m)]
  /\ cp'    = [cp    EXCEPT ![i][m.sender] = @ + 1]
  /\ store' = [store EXCEPT ![i][m.key] = ApplyWrite(@, <<m.val, V(m)>>)]

----------------------------------------------------------------------------
(* État initial                                                            *)

Init == /\ sent    = {}
        /\ lost    = {}
        /\ dlv     = [i \in Proc |-> <<>>]
        /\ cp      = [i \in Proc |-> Zero]
        /\ store   = [i \in Proc |-> [k \in Key |-> {}]]
        /\ crashed = {}
        /\ nput    = 0

----------------------------------------------------------------------------
(* Actions                                                                 *)

\* put(k, v) sur i : construire m, le diffuser, le délivrer tout de suite
Put(i, k, v) ==
  LET m == [sender |-> i, cp |-> cp[i], key |-> k, val |-> v] IN
  /\ i \notin crashed
  /\ nput < MaxPut
  /\ sent' = sent \cup {m}
  /\ DoDeliver(i, m)
  /\ nput' = nput + 1
  /\ UNCHANGED <<lost, crashed>>

\* i délivre un message diffusé par un autre
\* (en CO : seulement si DC est vraie ; en naïf : dès qu'il est là)
Deliver(i, m) ==
  /\ i \notin crashed
  /\ m \in sent
  /\ m \notin Delivered(i)
  /\ <<i, m>> \notin lost
  /\ Mode = "naive" \/ DC(i, m)
  /\ DoDeliver(i, m)
  /\ UNCHANGED <<sent, lost, crashed, nput>>

\* crash-stop de i.
\* En CO : i a déjà délivré ses propres messages, donc par URB-termination-2
\*         tous les corrects les délivreront ; rien n'est perdu.
\* En naïf : i a pu crasher au milieu de sa boucle d'envois ; certains
\*         destinataires ne recevront jamais ses messages.
Crash(i) ==
  /\ i \notin crashed
  /\ Cardinality(crashed) < MaxCrash
  /\ crashed' = crashed \cup {i}
  /\ IF Mode = "naive"
       THEN \E L \in SUBSET {<<j, m>> \in Proc \X sent : m.sender = i} :
              lost' = lost \cup L
       ELSE UNCHANGED lost
  /\ UNCHANGED <<sent, dlv, cp, store, nput>>

Next == \/ \E i \in Proc, k \in Key, v \in Val : Put(i, k, v)
        \/ \E i \in Proc, m \in sent : Deliver(i, m)
        \/ \E i \in Proc : Crash(i)

\* équité faible : une réplique qui peut délivrer finit par le faire
Spec == Init /\ [][Next]_vars /\ \A i \in Proc : WF_vars(\E m \in sent : Deliver(i, m))

----------------------------------------------------------------------------
(* Propriétés                                                              *)

\* plus grands éléments d'un ensemble de versions
Max(S) == {w \in S : ~\E w2 \in S : Lt(w[2], w2[2])}

\* versions de la clé k produites par les messages délivrés par i
Writes(i, k) == {<<m.val, V(m)>> : m \in {x \in Delivered(i) : x.key = k}}

TypeOK      == /\ nput \in 0..MaxPut
               /\ crashed \subseteq Proc
               /\ \A i \in Proc : cp[i] \in [Proc -> 0..MaxPut]

\* URB-validity : on ne délivre que des messages diffusés
Validity    == \A i \in Proc : Delivered(i) \subseteq sent

\* URB-integrity : chaque message délivré au plus une fois
Integrity   == \A i \in Proc : \A x, y \in 1..Len(dlv[i]) :
                 x # y => dlv[i][x] # dlv[i][y]

\* CO-URB message delivery : si V(m) < V(m'), m est délivré avant m'
CausalDelivery == \A i \in Proc : \A y \in 1..Len(dlv[i]) : \A m \in sent :
                    Lt(V(m), V(dlv[i][y])) => \E x \in 1..(y - 1) : dlv[i][x] = m

\* le store contient exactement les versions maximales des écritures délivrées
StoreInv    == \A i \in Proc, k \in Key : store[i][k] = Max(Writes(i, k))

\* mêmes écritures délivrées => même store, quel que soit l'ordre
Convergence == \A i, j \in Proc : Delivered(i) = Delivered(j) => store[i] = store[j]

\* URB-termination : à terme, chaque réplique non crashée a délivré tout ce qui
\* a été diffusé
AllDelivered == <>[](\A j \in Proc : j \in crashed \/ sent \subseteq Delivered(j))

THEOREM Spec => [](TypeOK /\ Validity /\ Integrity /\ CausalDelivery /\ StoreInv /\ Convergence)
THEOREM Spec => AllDelivered
=============================================================================
