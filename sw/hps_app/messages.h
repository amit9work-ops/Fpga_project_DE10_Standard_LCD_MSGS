#ifndef MESSAGES_H
#define MESSAGES_H

// 18 Messages for Rehabilitation/Treatment Room Display
// Navigate with: KEY1 (Next), KEY2 (Previous), KEY0 (Back)
static const char* MSG_LIST[18][4] = {
    
    // === WELCOME / STATUS ===
    {" Amit Damari ",        // Message 0: Welcome
     "                ",
     " Ido Zylberman  ",
     " today is 6 8 26"},   // ✅ Fixed: removed extra "},
    
    {" Eytan Mann     ",     // Message 1: Session begins
     "                ",
     " Project 3420   ",
     " Best Project   "},
    
    // === BREATHING EXERCISES ===
    {" TAU            ",     // Message 2
     "                ",
     " University     ",
     " Tel Aviv       "},
    
    {" Exercise 1 of 5",     // Message 3 - changed "/" to "of"
     "                ",
     " Breathe Out    ",
     " Slowly Calmly  "},    // changed "&" to word
    
    {" Exercise 2 of 5",     // Message 4
     "                ",
     " Deep Breath In ",
     " Count to 10    "},
    
    // === PHYSICAL EXERCISES ===
    {" Exercise 3 of 5",     // Message 5
     "                ",
     " Raise Arms Up  ",
     " Hold 10 Seconds"},
    
    {" Exercise 4 of 5",     // Message 6
     "                ",
     " Lower Arms Down",
     " Rest and Relax "},
    
    // === REST / BREAK ===
    {"    REST TIME   ",     // Message 7
     "                ",
     " Take a Break   ",
     " Drink Water    "},
    
    // === WAITING MESSAGES ===
    {" Please Wait    ",     // Message 8
     "                ",
     " Therapist Will ",
     " Be With You    "},
    
    {" Your Turn Soon ",     // Message 9
     "                ",
     " Stay Seated    ",
     " We Call You    "},
    
    // === INSTRUCTIONS ===
    {"  IMPORTANT     ",     // Message 10
     "                ",
     " Press Button   ",
     " If You Need Help"},
    
    {" Do Not Leave   ",     // Message 11
     "                ",
     " Stay In Room   ",
     " Until Called   "},
    
    // === STATUS MESSAGES ===
    {" Session Paused ",     // Message 12
     "                ",
     " Please Wait    ",
     " Will Resume    "},
    
    {" Session Active ",     // Message 13
     "                ",
     " In Progress    ",
     " Do Not Disturb "},
    
    // === COMPLETION ===
    {" Well Done      ",     // Message 14 - removed "!"
     "                ",
     " Exercise Set   ",
     " Completed      "},    // removed "!"
    
    {" Session Done   ",     // Message 15
     "                ",
     " Please Wait    ",
     " For Discharge  "},
    
    // === EMERGENCY / ALERTS ===
    {" ATTENTION      ",     // Message 16
     "                ",
     " Staff Called   ",
     " Help Coming    "},
    
    {" System Ready   ",     // Message 17
     "                ",
     " Press Any Key  ",
     " To Begin       "}
};

#endif // MESSAGES_H