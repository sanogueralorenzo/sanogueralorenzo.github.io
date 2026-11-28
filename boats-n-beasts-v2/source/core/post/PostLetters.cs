namespace BoatsNBeasts.Core;

public sealed record PostLetter(string Contents, string Letter, string Answer);

internal static class PostLetters
{
    internal static readonly PostLetter[][] Islands = [
        [
            new("a hinge sewn in sailcloth","Granddad, the keel is on the wrong side only when you are dry. I can prove it. Bring your good socks.","He arrives barefoot with his socks folded under his cap. He has already made his mind up about the boat."),
            new("the crust of a loaf","Every cell door here has two locks. Your bread door has one. Is that because it is easier to keep bread in or harder to keep me out?","A floury thumb has rubbed out the question mark. Underneath it the baker has written: Come for breakfast."),
            new("a slate rubbing","Una says our smoke curls left. I say it curls right. We ought to look from the same chimney before we stop speaking over it.","Each sister sends a sketch from the other roof. The postman puts them side by side and gets a perfectly ordinary cloud."),
            new("a pinch of warm sand","There is something knocking underneath my oven. If it is a baby I have only one question. Which side of the shell wants the blanket?","The answer is a drawing of a blanket under a little head. It is signed by six children who know about turtles.")
        ], [
            new("a pencil shaving","If the bank goes under, keep my chair. I like the notch where somebody before me counted up to nine.","Eda turns the chair over. On the underside an elderly hand has added one more notch."),
            new("a folded green leaf","My father could never pay for anything without checking the change. I want to take him on your ferry once while it costs a leaf.","Soss presses two leaves flat in the reply. One for coming back, he says. The other is for your father to check."),
            new("a bootlace eyelet","Alba, the coot has learned to come home. I am slower than the coot and my handwriting has got worse.","The reply has no stamp. It has a buttonhole. The traveling button fits exactly."),
            new("a paper ticket","If the audience has floated downriver, do we refund the tickets or carry on the play? There was a little girl in front. She had learned every line.","The little girl has written the next act herself. There is very good work in it for an actor who can swim.")
        ], [
            new("a thin pear cutting","Dad, if you must stay on that ladder could you pass me my coat? I was seven when I left it up there. It ought to fit my daughter.","The coat comes back wrapped around a cutting. A child's hand has drawn where the two sleeves used to be."),
            new("a moth scale","Pav says his soup comes with a story. Mine had a wing floating in it. The moth was still on the spoon asking to see the next course.","Pav has cut a saucer the size of a coin. He asks what time small customers dine."),
            new("a broken buckle","Gran, can I borrow the old wings? No, I am not asking to beat your time. Yes, I am asking to try.","Nim sends her old goggles and a fresh buckle. The note says to bring them home whether or not they win."),
            new("a blue shard","I thought glass was honest because you can see through it. Your trees had to teach me about reflections. Will you let me make you a window?","Sera sends the measurements of her kitchen and the height of a chair. She wants the apprentice to sit there and see the view.")
        ], [
            new("a mitten thumb","The hot tin came all the way upstairs. Whoever wore its mitt before me had a narrower thumb. Are they warm now?","Tavi writes down the address of every owner of the mitten. The letter has to go round twice before it comes home."),
            new("a strip of sheet music","Mum, I heard the pipes through the bathwater this morning. I think our house is a little flat. Shall I tell it?","Osa writes a rest into the music. On the next beat somebody who had never played before comes in beautifully."),
            new("a child's insole","You have printed my right boot as a bridge. The left one is still with me. If I walk home does that close the road?","Meri sends a chart with the two boots reunited. The road now has a dotted line and the word SOMETIMES."),
            new("a scrap of blue tin","Ren, that whistle never meant the ferry was safe. It meant I could see you on the bank. I wanted you to know the difference.","Ren folds the letter along the worn crease. He can hear the small difference now that he knows what to listen for.")
        ], [
            new("an unfinished button","A fastener has a decent working life even if it never meets its coat. Just the same, if you see a yellow coat missing its third button, tell me.","Sib sends a piece of green thread. The yellow coat has a new owner who likes to see where things have been mended."),
            new("a canvas handle","You carried me lying down. I have only ever seen you upside down. Would it be all right if I came to the ferry for another look?","Hal sets a chair the right way up. He sits in the other one and keeps both feet on the decking."),
            new("a stained apron tie","I put your blue in the family wash and turned the sheets the color of a storm. The baby slept through her first rough night.","Lume sends enough dye for another winter. The invoice is a request to hear what else the baby sleeps through."),
            new("a heel of rosin","Paz, you told me never to look down. All the people I am doing this for are down there. May I wave?","The answer is tied to the rope with a loose bow. It says to stop first, get both heels under you, and wave with your whole arm.")
        ], [
            new("a dented thimble","Four taps from cot eleven used to mean water. Now it means the fellow at the end of the ward has thought of the end of his joke.","Reva taps the punch line onto the bed rail. A ward full of people laughs in the wrong order."),
            new("a drop of bridge tar","Ume, when my boat went under the bridge you knocked on the rail. I was too far below to knock back. I have been meaning to answer you.","Ume writes that a hand laid flat against the rail can hear things a fist misses. There is a warm fingerprint in the tar."),
            new("a paper earhorn","You have kept the last words of all our pilots. My wife was a pilot too. Her last words were about a saucepan. Do those go in?","Tern makes room between two admirals. The saucepan turns out to have been a present and the instructions are quite good."),
            new("a corner of Tuesday","Oli, we have had three Mondays since my sister's birthday. She is prepared to have another birthday if that would help you find Tuesday.","Oli sends a square of Tuesday in a small tin. The sister chooses to use it for an ordinary afternoon.")
        ], [
            new("a copper rubbing","The clerk says there is no room on the ledger for half a fare. There was plenty of room on the ferry for half a sandwich, says my husband.","Ada holds the rubbing down with the change. She can read it now without laughing until she cries."),
            new("a wooden peg","Lev, I was the child under the witness chair. I heard everything they said about my mother. Could you make me a chair my size?","Lev draws one chair for the child and another for her mother. In his drawing both chairs face the same way."),
            new("a bell strap","Edda says a harbor can have a silent bell. My son wants to know how you tell when it has finished ringing.","A little flag comes with the answer. When every person on the quay has seen it, the last one lowers their hand."),
            new("a black heel of bread","We have a recipe for bread that keeps for a whole sentence. Could we have a recipe for the first thing to cook when you get out?","Mik writes eggs on toast. Then he writes where he will be on Sunday morning, and how many eggs to bring.")
        ], [
            new("a minute hand","Hester, your clock says I am older than Mum. May I tell her it is past her bedtime just this once?","Hester has marked the appropriate minute in red. It comes only once, so she suggests staying up together."),
            new("a little lead shoe","You weigh a ship empty and full. When we are all on deck laughing, the boat seems lighter. Is that recorded anywhere?","Tern makes a column beside ballast. He labels it Good Company and leaves the figures to the captain."),
            new("a green glass bead","Miri, there was an island in my kitchen window when I was small. Our house is gone. Has the island found another window?","Miri sends the bead on a thread. Held three fingers from the eye, it catches a small island with washing out."),
            new("a door hinge","Please deliver this to the door with no number on the street with no name. If you find it, please do not tell anybody else the way.","Elo signs on the back of the envelope. The postman is invited in for tea. The route home stays in his pocket.")
        ]
    ];
    internal static readonly string[] PublicMail = [
        "A ferry’s cargo is listed as forty empty bowls. Thirty-nine cooks have signed to say which people those bowls feed. One cook is out on the water.",
        "Nell has drawn houses on the dry half of the paper. Pell has put music on the wet half. Send the sheet round the delta so each ferryman can correct his own crossing.",
        "Ilo needs four signatures on an agreement to leave one lantern pear unpicked. The last space is for someone who works at night and sleeps through meetings.",
        "Anet asks the neighbors to join their hot-water pipes. Each home may draw one extra kettle for somebody who lives alone. Carry the agreement before the first hard freeze.",
        "Jo wrote a meal plan on a kitchen sail. Sailmakers on the four banks have offered to sew a square of their own if the cook will carry it to the clinic herself.",
        "The hospital boat is ready to sail without the registry. Four wards have to say where the patients want to go. Nell leaves room for a destination nobody has thought of.",
        "A clerk bound the verdicts into one book and the names of the witnesses into another. Pip volunteers to carry both books until every witness can find their own words.",
        "Gauge has ruled a blank page into four equal squares. Four places must decide what they want recorded about themselves before the needle can take the chart home.",
        "Uma has printed a walking terrace on four sheets. Each gardener may mark the last young root they found, even when that place is open water.",
        "Cella sends a nursery bottle with a breathing hole. Each orchard is to count the pairs passing through the migration road. Leave a line for any calf traveling alone.",
        "Kest asks four stations to sign the underside of a finish photograph. Whoever saw the family under the flying island should draw where they stood, even if they finished last.",
        "A child’s wax ear trumpet goes around the floating infirmary. Ask whether the sleeping shoal has the right to wake. Each patient who can write may answer in their own hand.",
        "Islet sends the old divers a scrap of lead line. Mark where you put your foot down when you found the street. The families want a map they can walk with their fingers.",
        "Ina sends Vara’s account on one side of the drumskin and Oren’s on the other. Each listener may add a separate line. Leave one beat empty for the young islands.",
        "Toma passes a split iron shackle round the old households. She asks where they want to raise the recovered dinner bell. The youngest people were born at sea.",
        "Pip has inked one footprint on the registry cover. Carry it to the nursery households and ask each to say what a growing island will need from the fleet."
    ];
}
